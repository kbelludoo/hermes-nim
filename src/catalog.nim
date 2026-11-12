import std/[httpclient, json, strutils, os]
import mbvm_native

type
  CommunitySkill* = object
    id*: string
    name*: string
    author*: string
    description*: string
    category*: string
    url*: string
    tags*: seq[string]

const DefaultCatalogUrl* = "https://raw.githubusercontent.com/kbelludoo/hermes-nim/main/catalog/community-skills.json"

proc parseCatalogJson*(jsonStr: string): seq[CommunitySkill] =
  result = @[]
  try:
    let parsed = parseJson(jsonStr)
    if parsed.kind == JArray:
      for item in parsed:
        var cs = CommunitySkill(
          id: item.getOrDefault("id").getStr(""),
          name: item.getOrDefault("name").getStr(""),
          author: item.getOrDefault("author").getStr(""),
          description: item.getOrDefault("description").getStr(""),
          category: item.getOrDefault("category").getStr(""),
          url: item.getOrDefault("url").getStr(""),
          tags: @[]
        )
        if item.hasKey("tags") and item["tags"].kind == JArray:
          for t in item["tags"]:
            cs.tags.add(t.getStr())
        if cs.id.len > 0:
          result.add(cs)
  except CatchableError:
    discard

proc loadLocalCatalog*(): seq[CommunitySkill] =
  let cands = [
    getCurrentDir() / "catalog" / "community-skills.json",
    getAppDir() / ".." / "catalog" / "community-skills.json",
    getAppDir() / "catalog" / "community-skills.json"
  ]
  for c in cands:
    if fileExists(c):
      try:
        return parseCatalogJson(readFile(c))
      except CatchableError:
        discard
  return @[]

proc fetchCommunitySkills*(catalogUrl: string = DefaultCatalogUrl): seq[CommunitySkill] =
  # 1. Try remote fetch
  try:
    var client = newHttpClient(timeout = 6_000)
    client.headers = newHttpHeaders({
      "User-Agent": "Hermes-Nim-Catalog/1.0"
    })
    let resp = client.getContent(catalogUrl)
    let parsed = parseCatalogJson(resp)
    if parsed.len > 0:
      return parsed
  except CatchableError:
    discard

  # 2. Fast local fallback (works offline)
  return loadLocalCatalog()

proc searchCommunitySkills*(catalog: seq[CommunitySkill], query: string): seq[CommunitySkill] =
  let qLower = query.strip().toLowerAscii()
  if qLower.len == 0: return catalog

  result = @[]
  for s in catalog:
    if s.id.toLowerAscii().contains(qLower) or
       s.name.toLowerAscii().contains(qLower) or
       s.description.toLowerAscii().contains(qLower) or
       s.category.toLowerAscii().contains(qLower):
      result.add(s)
      continue
    for t in s.tags:
      if t.toLowerAscii().contains(qLower):
        result.add(s)
        break

proc installCommunitySkill*(skillId: string, hermesHome: string, catalogUrl: string = DefaultCatalogUrl): tuple[success: bool, msg: string] =
  let catalog = fetchCommunitySkills(catalogUrl)
  var targetSkill: CommunitySkill
  var found = false

  for s in catalog:
    if s.id.toLowerAscii() == skillId.strip().toLowerAscii():
      targetSkill = s
      found = true
      break

  if not found:
    return (false, "Skill '" & skillId & "' not found in community catalog.")

  let destDir = hermesHome / "skills" / targetSkill.id
  let destFile = destDir / "SKILL.md"

  if not dirExists(destDir):
    createDir(destDir)

  # Check if local source exists first (instant offline install)
  let localSkillMd = getCurrentDir() / "skills" / targetSkill.id / "SKILL.md"
  if fileExists(localSkillMd):
    try:
      copyFile(localSkillMd, destFile)
      return (true, "Successfully installed skill '" & targetSkill.name & "' to " & destFile)
    except CatchableError as e:
      return (false, "Failed to copy local skill: " & e.msg)

  # Download from remote URL
  if targetSkill.url.startsWith("http://") or targetSkill.url.startsWith("https://"):
    try:
      var client = newHttpClient(timeout = 10_000)
      let content = client.getContent(targetSkill.url)
      writeFile(destFile, content)
      return (true, "Successfully downloaded and installed skill '" & targetSkill.name & "' to " & destFile)
    except CatchableError as e:
      return (false, "Failed to download skill from " & targetSkill.url & ": " & e.msg)

  return (false, "No valid installation source found for skill '" & skillId & "'.")

proc uninstallCommunitySkill*(skillId: string, hermesHome: string): tuple[success: bool, msg: string] =
  let targetDir = hermesHome / "skills" / skillId.strip().toLowerAscii()
  if dirExists(targetDir):
    try:
      removeDir(targetDir)
      return (true, "Successfully uninstalled skill '" & skillId & "'.")
    except CatchableError as e:
      return (false, "Failed to remove directory: " & e.msg)
  return (false, "Skill directory not found: " & targetDir)

proc indexCatalogIntoGraph*(catalog: seq[CommunitySkill], graph: ConversationGraph) =
  if graph == nil: return
  for s in catalog:
    let nodeName = "Skill:" & s.id
    var fields: seq[string] = @[
      "Category: " & s.category,
      "Author: " & s.author,
      "Description: " & s.description
    ]
    var aliases: seq[string] = s.tags
    aliases.add(s.id)
    aliases.add(s.name)
    aliases.add(s.category)

    discard graph.addNode(
      nkTopicDecision,
      nodeName,
      s.name,
      fields = fields,
      aliases = aliases
    )
