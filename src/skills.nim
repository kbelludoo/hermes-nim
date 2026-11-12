import std/[os, strutils, tables]

type
  Skill* = object
    name*: string
    description*: string
    path*: string
    content*: string

  SkillRegistry* = ref object
    skills*: Table[string, Skill]

proc parseSkillMd(filePath: string): Skill =
  result.path = filePath
  result.name = extractFilename(parentDir(filePath))
  result.description = ""
  
  try:
    let text = readFile(filePath)
    result.content = text
    
    # Simple frontmatter extractor
    if text.startsWith("---"):
      let endFm = text.find("---", 3)
      if endFm > 0:
        let fmBlock = text[3 ..< endFm]
        for line in fmBlock.splitLines():
          let t = line.strip()
          if t.startsWith("name:"):
            result.name = t[5 .. ^1].strip().replace("\"", "").replace("'", "")
          elif t.startsWith("description:"):
            result.description = t[12 .. ^1].strip().replace("\"", "").replace("'", "")
    
    if result.description.len == 0:
      # Use first non-empty line as description
      for line in text.splitLines():
        let t = line.strip()
        if t.len > 0 and not t.startsWith("#") and not t.startsWith("---"):
          result.description = if t.len > 120: t[0 ..< 120] & "..." else: t
          break
  except CatchableError:
    discard

proc newSkillRegistry*(hermesHome: string): SkillRegistry =
  new(result)
  result.skills = initTable[string, Skill]()

  let searchRoots = [
    getCurrentDir() / "skills",
    hermesHome / "skills",
    "C:\\Users\\kbell\\Downloads\\hermes-agent-main\\skills",
    getHomeDir() / ".hermes" / "skills"
  ]

  for root in searchRoots:
    if dirExists(root):
      for kind, path in walkDir(root):
        if kind == pcDir:
          let skillMd = path / "SKILL.md"
          if fileExists(skillMd):
            let s = parseSkillMd(skillMd)
            if s.name.len > 0 and not result.skills.hasKey(s.name):
              result.skills[s.name] = s

proc reload*(reg: SkillRegistry, hermesHome: string) =
  if reg == nil: return
  reg.skills.clear()
  let fresh = newSkillRegistry(hermesHome)
  for k, v in fresh.skills:
    reg.skills[k] = v

proc listSkills*(reg: SkillRegistry): string =
  if reg.skills.len == 0:
    return "No skills currently installed."
  
  var lines: seq[string] = @[]
  for name, s in reg.skills:
    lines.add("• " & name & ": " & (if s.description.len > 0: s.description else: "Custom skill"))
  return "Available Skills (" & $reg.skills.len & " loaded):\n" & lines.join("\n")

proc viewSkill*(reg: SkillRegistry, name: string): string =
  if reg.skills.hasKey(name):
    return reg.skills[name].content
  for k, s in reg.skills:
    if k.toLowerAscii() == name.toLowerAscii():
      return s.content
  return "Error: Skill '" & name & "' not found."
