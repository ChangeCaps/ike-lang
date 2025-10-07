use std::mem;

use crate::ir::{BodyId, Unit};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Generic {
    index: u64,
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
        body:     BodyId,
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

    Unknown,
    Error,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Field {
    pub name: String,
    pub ty:   Type,
}

impl Unit {
    pub fn is_subtype_of(&self, sub_type: &Type, super_type: &Type) -> bool {
        match (sub_type, super_type) {
            (Type::Never, _) => true,

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

                if variants.len() == 1 {
                    *ty = variants.pop().unwrap();
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
