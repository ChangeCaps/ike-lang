use crate::ir::BodyId;

#[derive(Clone, Debug)]
pub enum Type {
    Int,
    Float,
    Str,
    Bool,

    Body {
        body:     BodyId,
        generics: Vec<Type>,
    },

    Record {
        fields: Vec<Field>,
    },

    Union {
        variants: Vec<Type>,
    },

    Generic,

    Unknown,
}

#[derive(Clone, Debug)]
pub struct Field {
    pub name: String,
    pub ty:   Type,
}
