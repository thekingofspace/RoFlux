use std::path::Path;

use anyhow::{anyhow, Result};
use rbx_dom_weak::{InstanceBuilder, WeakDom};
use rbx_reflection::{DataType, PropertyDescriptor};
use rbx_types::{
    Attributes, BrickColor, CFrame, Color3, Content, Enum as RbxEnum, Matrix3, NumberRange, Rect,
    Tags, UDim, UDim2, Variant, VariantType, Vector2, Vector3,
};
use serde_json::Value;

use crate::ir::{Node, Ownership, Tree};
use crate::log;

fn number(value: &Value) -> Option<f64> {
    match value {
        Value::Number(inner) => inner.as_f64(),
        Value::Bool(inner) => Some(if *inner { 1.0 } else { 0.0 }),
        Value::String(inner) => inner.parse().ok(),
        _ => None,
    }
}

fn slot(value: &Value, key: &str, index: usize) -> f64 {
    if let Some(object) = value.as_object() {
        if let Some(found) = object.get(key).and_then(number) {
            return found;
        }
    }

    value
        .as_array()
        .and_then(|items| items.get(index))
        .and_then(number)
        .unwrap_or(0.0)
}

fn descriptor<'a>(class_name: &str, property: &str) -> Option<&'a PropertyDescriptor<'a>> {
    let database = rbx_reflection_database::get().ok()?;
    let mut cursor = Some(class_name.to_string());

    while let Some(name) = cursor {
        let class = database.classes.get(name.as_str())?;

        if let Some(found) = class.properties.get(property) {
            return Some(found);
        }

        cursor = class.superclass.as_ref().map(|value| value.to_string());
    }

    None
}

fn enum_value(enum_name: &str, value: &Value) -> Option<Variant> {
    let database = rbx_reflection_database::get().ok()?;
    let descriptor = database.enums.get(enum_name)?;

    if let Some(name) = value.as_str() {
        let found = descriptor.items.get(name)?;
        return Some(Variant::Enum(RbxEnum::from_u32(*found)));
    }

    let raw = number(value)? as u32;

    Some(Variant::Enum(RbxEnum::from_u32(raw)))
}

fn color(value: &Value) -> Color3 {
    let red = slot(value, "r", 0);
    let green = slot(value, "g", 1);
    let blue = slot(value, "b", 2);

    if red > 1.0 || green > 1.0 || blue > 1.0 {
        return Color3::new(red as f32 / 255.0, green as f32 / 255.0, blue as f32 / 255.0);
    }

    Color3::new(red as f32, green as f32, blue as f32)
}

fn udim(value: &Value) -> UDim {
    UDim::new(slot(value, "Scale", 0) as f32, slot(value, "Offset", 1) as i32)
}

fn udim2(value: &Value) -> UDim2 {
    if let Some(items) = value.as_array() {
        if items.len() == 2 && items[0].is_array() {
            return UDim2::new(udim(&items[0]), udim(&items[1]));
        }

        if items.len() == 4 {
            return UDim2::new(
                UDim::new(slot(value, "", 0) as f32, slot(value, "", 1) as i32),
                UDim::new(slot(value, "", 2) as f32, slot(value, "", 3) as i32),
            );
        }
    }

    UDim2::new(UDim::new(0.0, 0), UDim::new(0.0, 0))
}

fn cframe(value: &Value) -> CFrame {
    let items = value.as_array().cloned().unwrap_or_default();

    let position = Vector3::new(
        items.first().and_then(number).unwrap_or(0.0) as f32,
        items.get(1).and_then(number).unwrap_or(0.0) as f32,
        items.get(2).and_then(number).unwrap_or(0.0) as f32,
    );

    if items.len() < 12 {
        return CFrame::new(position, Matrix3::identity());
    }

    let read = |index: usize| items.get(index).and_then(number).unwrap_or(0.0) as f32;

    CFrame::new(
        position,
        Matrix3::new(
            Vector3::new(read(3), read(4), read(5)),
            Vector3::new(read(6), read(7), read(8)),
            Vector3::new(read(9), read(10), read(11)),
        ),
    )
}

fn convert(kind: VariantType, value: &Value) -> Option<Variant> {
    let converted = match kind {
        VariantType::String => Variant::String(match value {
            Value::String(text) => text.clone(),
            other => other.to_string(),
        }),
        VariantType::Bool => Variant::Bool(match value {
            Value::Bool(flag) => *flag,
            other => number(other).unwrap_or(0.0) != 0.0,
        }),
        VariantType::Float32 => Variant::Float32(number(value)? as f32),
        VariantType::Float64 => Variant::Float64(number(value)?),
        VariantType::Int32 => Variant::Int32(number(value)? as i32),
        VariantType::Int64 => Variant::Int64(number(value)? as i64),
        VariantType::Vector3 => Variant::Vector3(Vector3::new(
            slot(value, "x", 0) as f32,
            slot(value, "y", 1) as f32,
            slot(value, "z", 2) as f32,
        )),
        VariantType::Vector2 => Variant::Vector2(Vector2::new(
            slot(value, "x", 0) as f32,
            slot(value, "y", 1) as f32,
        )),
        VariantType::Color3 => Variant::Color3(color(value)),
        VariantType::UDim => Variant::UDim(udim(value)),
        VariantType::UDim2 => Variant::UDim2(udim2(value)),
        VariantType::CFrame => Variant::CFrame(cframe(value)),
        VariantType::BrickColor => {
            let found = value
                .as_str()
                .and_then(BrickColor::from_name)
                .or_else(|| number(value).and_then(|raw| BrickColor::from_number(raw as u16)))?;

            Variant::BrickColor(found)
        }
        VariantType::Content => Variant::Content(Content::from(value.as_str()?.to_string())),
        VariantType::ContentId => Variant::ContentId(value.as_str()?.to_string().into()),
        VariantType::NumberRange => Variant::NumberRange(NumberRange::new(
            slot(value, "min", 0) as f32,
            slot(value, "max", 1) as f32,
        )),
        VariantType::Rect => Variant::Rect(Rect::new(
            Vector2::new(slot(value, "", 0) as f32, slot(value, "", 1) as f32),
            Vector2::new(slot(value, "", 2) as f32, slot(value, "", 3) as f32),
        )),
        _ => return None,
    };

    Some(converted)
}

fn property(class_name: &str, key: &str, value: &Value) -> Option<Variant> {
    let Some(found) = descriptor(class_name, key) else {
        log::warn(format!("{class_name}.{key} is not a known property, skipping it in the place file"));
        return None;
    };

    match &found.data_type {
        DataType::Value(kind) => convert(*kind, value),
        DataType::Enum(name) => enum_value(name, value),
        _ => None,
    }
}

fn attributes(node: &Node) -> Option<Variant> {
    if node.attributes.is_empty() {
        return None;
    }

    let mut built = Attributes::new();

    for (key, value) in &node.attributes {
        let converted = match value {
            Value::String(text) => Variant::String(text.clone()),
            Value::Bool(flag) => Variant::Bool(*flag),
            Value::Number(_) => Variant::Float64(number(value)?),
            Value::Array(items) if items.len() == 3 => Variant::Vector3(Vector3::new(
                slot(value, "x", 0) as f32,
                slot(value, "y", 1) as f32,
                slot(value, "z", 2) as f32,
            )),
            _ => continue,
        };

        built.insert(key.clone(), converted);
    }

    Some(Variant::Attributes(built))
}

fn instance(node: &Node) -> InstanceBuilder {
    let mut builder = InstanceBuilder::new(node.class_name.clone()).with_name(node.name.clone());

    for (key, value) in &node.properties {
        if let Some(converted) = property(&node.class_name, key, value) {
            builder = builder.with_property(key.clone(), converted);
        }
    }

    if let Some(found) = attributes(node) {
        builder = builder.with_property("Attributes", found);
    }

    if !node.tags.is_empty() {
        let mut tags = Tags::new();

        for tag in &node.tags {
            tags.push(tag);
        }

        builder = builder.with_property("Tags", Variant::Tags(tags));
    }

    for child in &node.children {
        if child.ownership == Ownership::Reference {
            continue;
        }

        builder = builder.with_child(instance(child));
    }

    builder
}

pub fn dom(tree: &Tree) -> WeakDom {
    let synced = crate::patch::syncable(tree);
    let mut root = InstanceBuilder::new("DataModel").with_name(synced.root.name.clone());

    for child in &synced.root.children {
        root = root.with_child(instance(child));
    }

    WeakDom::new(root)
}

pub fn write_model(node: &Node, output: &Path) -> Result<()> {
    let dom = WeakDom::new(InstanceBuilder::new("Folder").with_name("RoFluxRoot"));
    let mut dom = dom;
    let root = dom.root_ref();
    dom.insert(root, instance(node));

    let roots = dom.root().children().to_vec();
    let file = std::fs::File::create(output)?;

    let extension = output
        .extension()
        .map(|value| value.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default();

    match extension.as_str() {
        "rbxmx" | "rbxlx" => rbx_xml::to_writer_default(file, &dom, &roots)?,
        _ => rbx_binary::to_writer(file, &dom, &roots)?,
    }

    Ok(())
}

pub fn write(tree: &Tree, output: &Path) -> Result<()> {
    let dom = dom(tree);
    let file = std::fs::File::create(output)?;
    let roots = dom.root().children().to_vec();

    let extension = output
        .extension()
        .map(|value| value.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default();

    match extension.as_str() {
        "rbxlx" | "rbxmx" => rbx_xml::to_writer_default(file, &dom, &roots)?,
        "rbxl" | "rbxm" => rbx_binary::to_writer(file, &dom, &roots)?,
        other => return Err(anyhow!("unsupported place format \".{other}\"")),
    }

    Ok(())
}
