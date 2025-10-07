use std::{
    mem,
    sync::atomic::{AtomicU64, Ordering},
};

use crate::ir::{BodyId, Unit};

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

    /// An record type.
    Record {
        fields: Vec<Field>,
    },

    /// A union type, e.g. `int | float`.
    Union {
        variants: Vec<Type>,
    },

    Generic {
        generic: Generic,
    },

    /// A type that is not known.
    Unknown,

    /// An type resulting from a compilation error.
    /// This type is never present in a valid program.
    Error,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Field {
    pub name: String,
    pub ty:   Type,
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
            | Type::Generic { .. } => true,

            Type::Unknown => false,

            Type::Body { generics, .. } => generics.iter().all(Type::is_known),
            Type::Record { fields } => fields.iter().all(|f| f.ty.is_known()),
            Type::Union { variants } => variants.iter().all(Type::is_known),
        }
    }
}

impl Unit {
    pub fn is_subtype_of(&self, sub_type: &Type, super_type: &Type) -> bool {
        match (sub_type, super_type) {
            (Type::Never, _) => true,
            (_, Type::Error) => true,
            (_, Type::Unknown) => true,

            (Type::Nat, Type::Int) => true,
            (Type::Nat, Type::Num) => true,
            (Type::Int, Type::Num) => true,

            (Type::Union { variants }, sup) => {
                variants.iter().all(|sub| self.is_subtype_of(sub, sup))
            }

            (sub, Type::Union { variants }) => {
                variants.iter().any(|sup| self.is_subtype_of(sub, sup))
            }

            (_, _) => sub_type == super_type,
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
            | Type::Generic { .. }
            | Type::Unknown
            | Type::Error => {}

            Type::Body { generics, .. } => {
                for generic in generics {
                    self.normalize_type(generic);
                }
            }

            Type::Record { fields } => {
                for field in fields {
                    self.normalize_type(&mut field.ty);
                }
            }

            Type::Union { variants } => {
                // simplifying unions is a little complicated, but essentially does two things
                //  1. remove all variants that are a subtype of another variant
                //  2. if only one variant is left, unwrap it

                let mut stack = mem::take(variants);

                'outer: while let Some(mut curr) = stack.pop() {
                    self.normalize_type(&mut curr);

                    if let Type::Union { variants } = curr {
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
