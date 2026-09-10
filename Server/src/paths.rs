pub fn split(path: &str) -> Vec<String> {
    path.split(['/', '.', '\\'])
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .map(str::to_string)
        .collect()
}

pub fn join(parts: &[String]) -> String {
    parts.join("/")
}

pub fn child(parent: &str, name: &str) -> String {
    if parent.is_empty() {
        name.to_string()
    } else {
        format!("{parent}/{name}")
    }
}
