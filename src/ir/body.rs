use crate::ir::{Expr, Generic, Pattern, Type};

#[derive(Clone, Debug)]
pub struct Body {
    pub name:     Option<String>,
    pub generics: Vec<GenericParameter>,
    pub locals:   Vec<Local>,
    pub params:   Vec<Parameter>,
    pub ty:       Type,
    pub expr:     Option<Expr>,
}

#[derive(Clone, Debug)]
pub struct GenericParameter {
    pub name:    Option<String>,
    pub generic: Generic,
}

#[derive(Clone, Debug)]
pub struct Parameter {
    pub pattern: Pattern,
    pub ty:      Type,
}

#[derive(Clone, Debug)]
pub struct Local {
    pub name: Option<String>,
    pub ty:   Type,
}
