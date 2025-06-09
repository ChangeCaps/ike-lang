mod r#type;

pub use r#type::*;

pub type Expr = super::Expr<Type>;
pub type ExprKind = super::ExprKind<Type>;
pub type Arm = super::Arm<Type>;
pub type BinOp = super::BinOp;
pub type Pattern = super::Pattern<Type>;
pub type PatternKind = super::PatternKind<Type>;

pub type Local = super::Local<Type>;
pub type Locals = super::Locals<Type>;
pub type Lid = super::Lid<Type>;

pub type Body = super::Body<Type>;
pub type Bodies = super::Bodies<Type>;
pub type Bid = super::Bid<Type>;

#[derive(Clone, Debug, PartialEq)]
pub struct Program {
    pub bodies: Bodies,
    pub types: Types,
}

impl Default for Program {
    fn default() -> Self {
        Self::new()
    }
}

impl Program {
    pub fn new() -> Self {
        Self {
            bodies: Bodies::default(),
            types: Types::default(),
        }
    }
}
