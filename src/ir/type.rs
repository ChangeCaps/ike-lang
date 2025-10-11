use std::{
    collections::HashMap,
    sync::atomic::{AtomicU64, Ordering},
};

use crate::ir::{AliasId, BodyId, NewtypeId, Unit};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Generic {
    index: u64,
}

impl Default for Generic {
    fn default() -> Self {
        Self::new()
    }
}

impl Generic {
    pub fn new() -> Self {
        static NEXT_INDEX: AtomicU64 = AtomicU64::new(0);

        Self {
            index: NEXT_INDEX.fetch_add(1, Ordering::SeqCst),
        }
    }
}

#[derive(Clone, Debug)]
pub struct GenericParameter {
    pub name:             Option<String>,
    pub generic:          Generic,
    pub is_covariant:     bool,
    pub is_contravariant: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Type {
    /// The natural number type.
    Nat,

    /// The integer type.
    Int,

    /// The floating point type.
    Num,

    /// The string type.
    Str,

    /// The boolean type.
    Bool,

    /// The none type.
    None,

    /// The never type.
    Never,

    /// The type of a specific [`Body`], specialized with `generics`.
    Body {
        body_id:  BodyId,
        generics: Vec<Type>,
    },

    Alias {
        alias_id: AliasId,
        generics: Vec<Type>,
    },

    Newtype {
        newtype_id: NewtypeId,
        generics:   Vec<Type>,
    },

    List(Box<Type>),

    Fn(Vec<Type>, Box<Type>),

    /// An record type.
    Record(Vec<TypeField>),

    /// A union type, e.g. `int | float`.
    Union(Vec<Type>),

    /// A generic type.
    Generic(Generic),

    /// A type that is not known.
    Unknown,

    /// An type resulting from a compilation error.
    /// This type is never present in a valid program.
    Error,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TypeField {
    pub name: String,
    pub ty:   Type,
}

#[derive(Clone, Debug)]
pub struct Alias {
    pub name:     Option<String>,
    pub generics: Vec<GenericParameter>,
    pub ty:       Type,
}

#[derive(Clone, Debug)]
pub struct Newtype {
    pub name:     Option<String>,
    pub generics: Vec<GenericParameter>,
    pub ty:       Type,
}

impl Type {
    pub fn is_known(&self) -> bool {
        match self {
            Type::Nat
            | Type::Int
            | Type::Num
            | Type::Str
            | Type::Bool
            | Type::None
            | Type::Never
            | Type::Error
            | Type::Generic(..) => true,

            Type::Unknown => false,

            Type::List(elem) => elem.is_known(),

            Type::Fn(inputs, output) => inputs.iter().all(|t| t.is_known()) && output.is_known(),

            Type::Body { generics, .. }
            | Type::Alias { generics, .. }
            | Type::Newtype { generics, .. } => generics.iter().all(Type::is_known),
            Type::Record(fields) => fields.iter().all(|f| f.ty.is_known()),
            Type::Union(variants) => variants.iter().all(Type::is_known),
        }
    }

    pub fn instantiate(&mut self, map: &HashMap<Generic, Type>) {
        match self {
            Type::Nat
            | Type::Int
            | Type::Num
            | Type::Str
            | Type::Bool
            | Type::None
            | Type::Never
            | Type::Unknown
            | Type::Error => {}

            Type::Body { generics, .. }
            | Type::Alias { generics, .. }
            | Type::Newtype { generics, .. } => {
                for generic in generics {
                    generic.instantiate(map);
                }
            }

            Type::List(elem) => elem.instantiate(map),

            Type::Fn(inputs, output) => {
                for input in inputs {
                    input.instantiate(map);
                }

                output.instantiate(map);
            }

            Type::Record(fields) => {
                for field in fields {
                    field.ty.instantiate(map);
                }
            }

            Type::Union(variants) => {
                for variant in variants {
                    variant.instantiate(map);
                }
            }

            Type::Generic(generic) => match map.get(generic) {
                Some(s) => *self = s.clone(),
                None => *self = Type::Unknown,
            },
        }
    }
}

impl Unit {
    pub fn format_type(&self, ty: &Type) -> String {
        match ty {
            Type::Nat => String::from("nat"),
            Type::Int => String::from("int"),
            Type::Num => String::from("num"),
            Type::Str => String::from("str"),
            Type::Bool => String::from("bool"),
            Type::None => String::from("none"),
            Type::Never => String::from("!"),
            Type::Unknown => String::from("unknown"),
            Type::Error => String::from("error"),

            Type::Body { body_id, generics } => {
                let generics = self.format_generics(generics);

                match self[*body_id].name {
                    Some(ref name) => format!("{{{name}}}{generics}"),
                    None => format!("{{fn}}{generics}"),
                }
            }

            Type::Alias { alias_id, generics } => {
                let generics = self.format_generics(generics);

                match self[*alias_id].name {
                    Some(ref name) => format!("{name}{generics}"),
                    None => format!("{{alias}}{generics}"),
                }
            }

            Type::Newtype {
                newtype_id,
                generics,
            } => {
                let generics = self.format_generics(generics);

                match self[*newtype_id].name {
                    Some(ref name) => format!("{name}{generics}"),
                    None => format!("{{type}}{generics}"),
                }
            }

            Type::List(elem) => format!("[{}]", self.format_type(elem)),

            Type::Fn(inputs, output) => {
                let inputs = inputs
                    .iter()
                    .map(|t| self.format_type(t))
                    .collect::<Vec<_>>()
                    .join(", ");

                match output.as_ref() {
                    Type::None => format!("fn({inputs})"),
                    output => format!("fn({inputs}) -> {}", self.format_type(output)),
                }
            }

            Type::Record(fields) => {
                let fields = fields
                    .iter()
                    .map(|f| {
                        let ty = self.format_type(&f.ty);
                        format!("{}: {ty}", f.name)
                    })
                    .collect::<Vec<_>>()
                    .join(", ");

                match fields.is_empty() {
                    true => String::from("{}"),
                    false => format!("{{ {fields} }}"),
                }
            }

            Type::Union(items) => items
                .iter()
                .map(|t| self.format_type(t))
                .collect::<Vec<_>>()
                .join(" | "),

            Type::Generic(..) => String::from("'_"),
        }
    }

    fn format_generics(&self, generics: &[Type]) -> String {
        let generics = generics
            .iter()
            .map(|t| self.format_type(t))
            .collect::<Vec<_>>()
            .join(", ");

        match generics.is_empty() {
            true => String::new(),
            false => format!("<{generics}>"),
        }
    }

    pub fn instantiate_alias(&self, alias_id: AliasId, generics: &[Type]) -> Type {
        assert_eq!(self[alias_id].generics.len(), generics.len());

        let map = self[alias_id]
            .generics
            .iter()
            .map(|p| p.generic)
            .zip(generics.iter().cloned())
            .collect();

        let mut ty = self[alias_id].ty.clone();
        ty.instantiate(&map);
        ty
    }

    pub fn instantiate_newtype(&self, newtype_id: NewtypeId, generics: &[Type]) -> Type {
        assert_eq!(self[newtype_id].generics.len(), generics.len());

        let map = self[newtype_id]
            .generics
            .iter()
            .map(|p| p.generic)
            .zip(generics.iter().cloned())
            .collect();

        let mut ty = self[newtype_id].ty.clone();
        ty.instantiate(&map);
        ty
    }

    pub fn is_subtype_of(&self, sub_type: &Type, super_type: &Type) -> bool {
        if sub_type == super_type {
            return true;
        }

        match (sub_type, super_type) {
            (Type::Never, _) => true,
            (_, Type::Unknown) => true,
            (Type::Error, _) | (_, Type::Error) => true,

            (Type::Nat, Type::Int) => true,
            (Type::Nat, Type::Num) => true,
            (Type::Int, Type::Num) => true,

            (Type::Union(sub_variants), Type::Union(super_variants)) => {
                let sub_variants = self.normalize_union(sub_variants);
                let super_variants = self.normalize_union(super_variants);

                sub_variants.iter().all(|sub_type| {
                    super_variants.iter().any(|super_type| {
                        // check pair
                        self.is_subtype_of(sub_type, super_type)
                    })
                }) && super_variants.iter().all(|super_type| {
                    sub_variants.iter().any(|sub_type| {
                        // check pair
                        self.is_subtype_of(sub_type, super_type)
                    })
                })
            }

            (Type::List(sub_type), Type::List(super_type)) => {
                self.is_subtype_of(sub_type, super_type)
            }

            (Type::Fn(sub_inputs, sub_output), Type::Fn(super_inputs, super_output)) => {
                if sub_inputs.len() != super_inputs.len() {
                    return false;
                }

                for (sub_input, super_input) in sub_inputs.iter().zip(super_inputs) {
                    if !self.is_subtype_of(super_input, sub_input) {
                        return false;
                    }
                }

                self.is_subtype_of(sub_output, super_output)
            }

            (Type::Record(sub_fields), Type::Record(super_fields)) => {
                if sub_fields.len() != super_fields.len() {
                    return false;
                }

                super_fields.iter().all(|super_field| {
                    sub_fields.iter().any(|sub_field| {
                        sub_field.name == super_field.name
                            && self.is_subtype_of(&sub_field.ty, &super_field.ty)
                    })
                })
            }

            (Type::Alias { alias_id, generics }, super_type) => {
                let sub_type = self.instantiate_alias(*alias_id, generics);
                self.is_subtype_of(&sub_type, super_type)
            }

            (sub_type, Type::Alias { alias_id, generics }) => {
                let super_type = self.instantiate_alias(*alias_id, generics);
                self.is_subtype_of(sub_type, &super_type)
            }

            (
                Type::Newtype {
                    newtype_id: sub_id,
                    generics: sub_generics,
                },
                Type::Newtype {
                    newtype_id: super_id,
                    generics: super_generics,
                },
            ) if sub_id == super_id => {
                let sub_type = self.instantiate_newtype(*sub_id, sub_generics);
                let super_type = self.instantiate_newtype(*super_id, super_generics);

                self.is_subtype_of(&sub_type, &super_type)
            }

            (_, _) => false,
        }
    }

    pub fn normalize_type(&self, ty: &mut Type) {
        match ty {
            Type::Nat
            | Type::Int
            | Type::Num
            | Type::Str
            | Type::Bool
            | Type::None
            | Type::Never
            | Type::Generic(..)
            | Type::Unknown
            | Type::Error => {}

            Type::Body { generics, .. }
            | Type::Alias { generics, .. }
            | Type::Newtype { generics, .. } => {
                for generic in generics {
                    self.normalize_type(generic);
                }
            }

            Type::List(elem) => self.normalize_type(elem),

            Type::Fn(inputs, output) => {
                for input in inputs {
                    self.normalize_type(input);
                }

                self.normalize_type(output);
            }

            Type::Record(fields) => {
                for field in fields {
                    self.normalize_type(&mut field.ty);
                }
            }

            Type::Union(variants) => {
                // normalizing unions is a little complicated, but essentially does two things
                //  1. remove all variants that are a subtype of another variant
                //  2. if only one variant is left, unwrap it

                let mut stack = self.normalize_union(variants);
                variants.clear();

                'outer: while let Some(mut curr) = stack.pop() {
                    self.normalize_type(&mut curr);

                    if let Type::Union(variants) = curr {
                        stack.extend(variants);
                        continue;
                    }

                    for var in variants.iter_mut() {
                        if self.is_subtype_of(&curr, var) {
                            continue 'outer;
                        }

                        if self.is_subtype_of(var, &curr) {
                            *var = curr;
                            continue 'outer;
                        }
                    }

                    variants.push(curr);
                }

                match variants.len() {
                    0 => *ty = Type::Never,
                    1 => *ty = variants.pop().unwrap(),
                    _ => {}
                }
            }
        }
    }

    fn normalize_union(&self, variants: &[Type]) -> Vec<Type> {
        let mut stack = Vec::new();

        for mut variant in variants.iter().cloned() {
            while let Type::Alias { alias_id, generics } = variant {
                variant = self.instantiate_alias(alias_id, &generics);
            }

            match variant {
                Type::Union(variants) => {
                    let variants = self.normalize_union(&variants);
                    stack.extend(variants);
                }

                _ => stack.push(variant),
            }
        }

        stack
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_subtype_of_numbers() {
        let unit = Unit::new();

        assert!(unit.is_subtype_of(&Type::Nat, &Type::Nat));
        assert!(unit.is_subtype_of(&Type::Nat, &Type::Int));
        assert!(unit.is_subtype_of(&Type::Nat, &Type::Num));
        assert!(unit.is_subtype_of(&Type::Int, &Type::Num));
    }
}
