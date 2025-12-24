use quick_xml::events::Event;
use quick_xml::reader::Reader;
use std::io::{self, BufRead};

fn escape(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

fn format_event(reader: &Reader<&[u8]>, event: &Event) -> String {
    match event {
        Event::Start(e) => {
            let name = String::from_utf8_lossy(e.name().as_ref()).to_string();
            let attrs: Vec<String> = e.attributes()
                .filter_map(|a| a.ok())
                .map(|a| {
                    let k = String::from_utf8_lossy(a.key.as_ref()).to_string();
                    let v = a.decode_and_unescape_value(reader.decoder()).unwrap_or_default().to_string();
                    format!("(\"{}\", \"{}\")", escape(&k), escape(&v))
                })
                .collect();
            format!("Start({{name: \"{}\", attributes: [{}]}})", escape(&name), attrs.join(", "))
        }
        Event::End(e) => {
            let name = String::from_utf8_lossy(e.name().as_ref()).to_string();
            format!("End(\"{}\")", escape(&name))
        }
        Event::Empty(e) => {
            let name = String::from_utf8_lossy(e.name().as_ref()).to_string();
            let attrs: Vec<String> = e.attributes()
                .filter_map(|a| a.ok())
                .map(|a| {
                    let k = String::from_utf8_lossy(a.key.as_ref()).to_string();
                    let v = a.decode_and_unescape_value(reader.decoder()).unwrap_or_default().to_string();
                    format!("(\"{}\", \"{}\")", escape(&k), escape(&v))
                })
                .collect();
            format!("Empty({{name: \"{}\", attributes: [{}]}})", escape(&name), attrs.join(", "))
        }
        Event::Text(e) => {
            let text = e.unescape().unwrap_or_default();
            format!("Text(\"{}\")", escape(&text))
        }
        Event::CData(e) => {
            let text = String::from_utf8_lossy(e);
            format!("CData(\"{}\")", escape(&text))
        }
        Event::Comment(e) => {
            let text = String::from_utf8_lossy(e);
            format!("Comment(\"{}\")", escape(&text))
        }
        Event::PI(e) => {
            let content = String::from_utf8_lossy(e);
            let parts: Vec<&str> = content.splitn(2, char::is_whitespace).collect();
            let target = parts.first().unwrap_or(&"");
            let data = parts.get(1).unwrap_or(&"");
            format!("PI(target=\"{}\", data=\"{}\")", escape(target), escape(data))
        }
        Event::Decl(e) => {
            let version = e.version().ok().map(|v| String::from_utf8_lossy(&v).to_string()).unwrap_or_default();
            let encoding = e.encoding().and_then(|r| r.ok()).map(|e| format!("Some(\"{}\")", escape(&String::from_utf8_lossy(&e)))).unwrap_or_else(|| "None".to_string());
            let standalone = e.standalone().and_then(|r| r.ok()).map(|s| format!("Some(\"{}\")", escape(&String::from_utf8_lossy(&s)))).unwrap_or_else(|| "None".to_string());
            format!("Decl(version=\"{}\", encoding={}, standalone={})", escape(&version), encoding, standalone)
        }
        Event::DocType(e) => {
            let content = String::from_utf8_lossy(e);
            let name = content.split_whitespace().next().unwrap_or(&content);
            format!("DocType(\"{}\")", escape(name))
        }
        Event::Eof => "Eof".to_string(),
    }
}

fn parse_and_print(xml: &str) {
    let mut reader = Reader::from_str(xml);
    reader.config_mut().trim_text(false);

    let mut events = Vec::new();

    loop {
        match reader.read_event() {
            Ok(ref event) => {
                events.push(format_event(&reader, event));
                if matches!(event, Event::Eof) {
                    break;
                }
            }
            Err(e) => {
                events.push(format!("Error(\"{}\")", escape(&e.to_string())));
                break;
            }
        }
    }

    println!("[{}]", events.join(", "));
}

fn unescape_input(s: &str) -> String {
    let mut result = String::new();
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some('n') => result.push('\n'),
                Some('r') => result.push('\r'),
                Some('t') => result.push('\t'),
                Some('\\') => result.push('\\'),
                Some(other) => {
                    result.push('\\');
                    result.push(other);
                }
                None => result.push('\\'),
            }
        } else {
            result.push(c);
        }
    }
    result
}

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if !line.is_empty() {
            let xml = unescape_input(&line);
            parse_and_print(&xml);
        }
    }
}
