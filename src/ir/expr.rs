use std::fmt;

use crate::{
    diagnostic::Span,
    ir::{BodyId, NewtypeId, Pattern, Type},
};

#[derive(Clone, Debug)]
pub struct Expr {
    pub kind: ExprKind,
    pub ty:   Type,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum ExprKind {
    Num(i64),
    Str(String),
    Bool(bool),
    None,
    Body(BodyId),
    Let(Pattern, Box<Expr>),
    Local(usize),
    Union(Box<Expr>),
    Promote(NewtypeId, Box<Expr>),
    Demote(NewtypeId, Box<Expr>),
    CallBody(BodyId, Vec<Type>, Vec<Expr>),
    Binary(BinOp, Box<Expr>, Box<Expr>),
    Record(Vec<ExprField>),
    Block(Vec<Expr>),
    Error,
}

#[derive(Clone, Debug)]
pub struct ExprField {
    pub name: String,
    pub expr: Expr,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Lt,
    Gt,
    Le,
    Ge,
    Eq,
    Ne,
}

impl fmt::Display for BinOp {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BinOp::Add => write!(f, "add"),
            BinOp::Sub => write!(f, "sub"),
            BinOp::Mul => write!(f, "mul"),
            BinOp::Div => write!(f, "div"),
            BinOp::Mod => write!(f, "mod"),
            BinOp::Lt => write!(f, "<"),
            BinOp::Gt => write!(f, ">"),
            BinOp::Le => write!(f, "<="),
            BinOp::Ge => write!(f, ">="),
            BinOp::Eq => write!(f, "=="),
            BinOp::Ne => write!(f, "!="),
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
