use serde_json::Value;

const KEYWORDS: &[&str] = &[
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local",
    "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "continue", "export",
    "type", "const",
];

fn identifier(name: &str) -> bool {
    if name.is_empty() || KEYWORDS.contains(&name) {
        return false;
    }

    let mut chars = name.chars();

    let head = chars.next().unwrap_or_default();

    if !head.is_ascii_alphabetic() && head != '_' {
        return false;
    }

    chars.all(|value| value.is_ascii_alphanumeric() || value == '_')
}

pub fn quote(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');

    for value in text.chars() {
        match value {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            value if (value as u32) < 0x20 => out.push_str(&format!("\\{}", value as u32)),
            value => out.push(value),
        }
    }

    out.push('"');
    out
}

pub fn emit(value: &Value) -> String {
    write(value, 0)
}

fn write(value: &Value, depth: usize) -> String {
    let pad = "\t".repeat(depth + 1);
    let close = "\t".repeat(depth);

    match value {
        Value::Null => "nil".into(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => quote(value),
        Value::Array(items) => {
            if items.is_empty() {
                return "{}".into();
            }

            let body = items
                .iter()
                .map(|item| format!("{pad}{},", write(item, depth + 1)))
                .collect::<Vec<_>>()
                .join("\n");

            format!("{{\n{body}\n{close}}}")
        }
        Value::Object(fields) => {
            if fields.is_empty() {
                return "{}".into();
            }

            let body = fields
                .iter()
                .map(|(key, item)| {
                    let slot = if identifier(key) {
                        key.clone()
                    } else {
                        format!("[{}]", quote(key))
                    };

                    format!("{pad}{slot} = {},", write(item, depth + 1))
                })
                .collect::<Vec<_>>()
                .join("\n");

            format!("{{\n{body}\n{close}}}")
        }
    }
}
