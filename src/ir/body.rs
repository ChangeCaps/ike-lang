use crate::ir::{Expr, Pattern, Type};

#[derive(Clone, Debug)]
pub struct Body {
    pub name:   Option<String>,
    pub locals: Vec<Local>,
    pub params: Vec<Parameter>,
    pub ty:     Type,
    pub expr:   Option<Expr>,
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
