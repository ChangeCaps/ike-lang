use std::fmt;

use crate::{
    diagnostic::Span,
    ir::{BodyId, Pattern, Type},
};

#[derive(Clone, Debug)]
pub struct Expr {
    pub kind: ExprKind,
    pub ty:   Type,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum ExprKind {
    Int(i64),
    Float(f64),
    Str(String),
    Bool(bool),
    Body(BodyId),
    Let(Pattern, Box<Expr>),
    Local(usize),
    CallBody(BodyId, Vec<Type>, Vec<Expr>),
    Binary(BinOp, Box<Expr>, Box<Expr>),
    Block(Vec<Expr>),
    Error,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
}

impl fmt::Display for BinOp {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BinOp::Add => write!(f, "add"),
            BinOp::Sub => write!(f, "sub"),
            BinOp::Mul => write!(f, "mul"),
            BinOp::Div => write!(f, "div"),
            BinOp::Mod => write!(f, "mod"),
        }
    }
}

impl Expr {
    pub fn error(span: Span) -> Self {
        Expr {
            kind: ExprKind::Error,
            ty: Type::Error,
            span,
        }
    }
}
