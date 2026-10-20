///|
/// Built-in character set presets for web fonts and typography optimization.

///|
/// ASCII printable characters (space through tilde, 32..126)
pub fn get_ascii_preset() -> Array[Int] {
  let list : Array[Int] = []
  for cp = 32; cp <= 126; cp = cp + 1 {
    list.push(cp)
  }
  list
}

///|
/// Digits 0-9
pub fn get_digits_preset() -> Array[Int] {
  let list : Array[Int] = []
  for cp = '0'.to_int(); cp <= '9'.to_int(); cp = cp + 1 {
    list.push(cp)
  }
  list
}

///|
/// Alphanumeric characters (0-9, a-z, A-Z)
pub fn get_alphanumeric_preset() -> Array[Int] {
  let list : Array[Int] = []
  for cp = '0'.to_int(); cp <= '9'.to_int(); cp = cp + 1 {
    list.push(cp)
  }
  for cp = 'A'.to_int(); cp <= 'Z'.to_int(); cp = cp + 1 {
    list.push(cp)
  }
  for cp = 'a'.to_int(); cp <= 'z'.to_int(); cp = cp + 1 {
    list.push(cp)
  }
  list
}

///|
/// Common high-frequency Chinese characters and punctuation.
pub fn get_chinese_common_preset() -> Array[Int] {
  let text = "的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应开它合还因由其些然前外天政四日那社义事平形相全表间样想向道命此变条只没结问第非常心各月理门军建受反更任件党西总色身清由转么知或但无定题正文新已明做目走将看日重真强长教气白安保位，。！？、“”《》：；"
  let list : Array[Int] = []
  for c in text {
    list.push(c.to_int())
  }
  list
}

///|
/// Lookup preset by name. Supports: "ascii", "digits", "alphanumeric", "chinese", "sc"
pub fn get_preset_by_name(name : String) -> Array[Int]? {
  let lower = name.to_lower()
  if lower == "ascii" {
    Some(get_ascii_preset())
  } else if lower == "digits" || lower == "numbers" {
    Some(get_digits_preset())
  } else if lower == "alphanumeric" || lower == "alnum" {
    Some(get_alphanumeric_preset())
  } else if lower == "chinese" || lower == "sc" || lower == "cjk" {
    Some(get_chinese_common_preset())
  } else {
    None
  }
}
