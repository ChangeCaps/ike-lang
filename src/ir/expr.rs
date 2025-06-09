use crate::diagnostic::Span;

use super::{Bid, Lid};

#[derive(Clone, Debug, PartialEq)]
pub enum ExprKind<T> {
    Int(i64),
    Bool(bool),
    String(String),
    Local(Lid<T>),
    Body(Bid<T>),
    Let(Pattern<T>, Box<Expr<T>>),
    Variant(String, Option<Box<Expr<T>>>),
    ListEmpty,
    ListCons(Box<Expr<T>>, Box<Expr<T>>),
    Tuple(Vec<Expr<T>>),
    Record(Vec<(String, Expr<T>)>),
    Call(Box<Expr<T>>, Box<Expr<T>>),
    Binary(BinOp, Box<Expr<T>>, Box<Expr<T>>),
    Match(Box<Expr<T>>, Vec<Arm<T>>),
    Field(Box<Expr<T>>, String),
    Block(Vec<Expr<T>>),
}

#[derive(Clone, Debug, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    And,
    Or,
    Gt,
    Lt,
    Ge,
    Le,
    Eq,
    Ne,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Arm<T> {
    pub pattern: Pattern<T>,
    pub expr: Expr<T>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Expr<T> {
    pub kind: ExprKind<T>,
    pub span: Span,
    pub ty: T,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Pattern<T> {
    pub kind: PatternKind<T>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum PatternKind<T> {
    Wildcard,
    Binding(Lid<T>),
    Tuple(Vec<Pattern<T>>),
    Bool(bool),
    Variant(T, String, Option<Box<Pattern<T>>>),
    ListEmpty,
    ListCons(Box<Pattern<T>>, Box<Pattern<T>>),
}

impl<T> PatternKind<T> {
    pub fn is_refutable(&self) -> bool {
        match self {
            Self::Wildcard | Self::Binding(_) => false,
            Self::Bool(_) | Self::ListEmpty | Self::ListCons(_, _) | Self::Variant(_, _, _) => true,

            Self::Tuple(patterns) => patterns.iter().any(|p| p.kind.is_refutable()),
        }
    }
}
