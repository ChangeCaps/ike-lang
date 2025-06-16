use std::{fmt, ops::Deref};

use crate::diagnostic::Span;

#[derive(Clone, Debug, PartialEq)]
pub struct Module {
    pub items: Vec<Item>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Path {
    pub segments: Vec<String>,
    pub generics: Vec<Type>,
    pub span: Span,
}

impl Path {
    pub fn name(&self) -> &str {
        self.segments.last().unwrap()
    }

    pub fn modules(&self) -> impl ExactSizeIterator<Item = &str> {
        self.segments
            .iter()
            .take(self.segments.len() - 1)
            .map(Deref::deref)
    }
}

impl fmt::Display for Path {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.segments.join("::").fmt(f)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum ExprKind {
    Int(i64),
    Bool(bool),
    String(String),
    Path(Path),
    Let(Pattern, Box<Expr>),
    Record(Path, Vec<(String, Expr)>),
    List(Vec<Expr>, Option<Box<Expr>>),
    Tuple(Vec<Expr>),
    Lambda(Vec<Pattern>, Box<Expr>),
    Binary(BinOp, Box<Expr>, Box<Expr>),
    Call(Box<Expr>, Box<Expr>),
    Field(Box<Expr>, String),
    Match(Box<Expr>, Vec<Arm>),
    Block(Vec<Expr>),
}

impl ExprKind {
    pub fn with_span(self, span: Span) -> Expr {
        Expr { kind: self, span }
    }
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
pub struct Arm {
    pub pattern: Pattern,
    pub expr: Expr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Expr {
    pub kind: ExprKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum PatternKind {
    Wildcard,
    Path(Path),
    Variant(Path, Box<Pattern>),
    Tuple(Vec<Pattern>),
    Bool(bool),
    List(Vec<Pattern>, Option<Box<Pattern>>),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Pattern {
    pub kind: PatternKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum TypeKind {
    Int,
    Str,
    Bool,
    Unit,
    Path(Path),
    List(Box<Type>),
    Tuple(Vec<Type>),
    Function(Box<Type>, Box<Type>),
    Generic(String),
    Inferred,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Type {
    pub kind: TypeKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ItemName {
    pub segments: Vec<String>,
    pub span: Span,
}

impl ItemName {
    pub fn modules(&self) -> impl ExactSizeIterator<Item = &str> {
        self.segments
            .iter()
            .take(self.segments.len() - 1)
            .map(Deref::deref)
    }

    pub fn name(&self) -> &str {
        self.segments.last().unwrap()
    }

    pub fn segments(&self) -> impl ExactSizeIterator<Item = &str> {
        self.segments.iter().map(Deref::deref)
    }
}

impl fmt::Display for ItemName {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.segments.join("::").fmt(f)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Function {
    pub name: ItemName,
    pub params: Vec<Pattern>,
    pub body: Option<Expr>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Newtype {
    pub name: ItemName,
    pub generics: Vec<String>,
    pub kind: NewtypeKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum NewtypeKind {
    Union(Vec<Variant>),
    Record(Vec<Field>),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Variant {
    pub name: String,
    pub ty: Option<Type>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Field {
    pub name: String,
    pub ty: Type,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Import {
    pub path: Path,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Ascription {
    pub name: ItemName,
    pub ty: Type,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Extern {
    pub name: ItemName,
    pub ty: Type,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Item {
    Import(Import),
    Newtype(Newtype),
    Function(Function),
    Ascription(Ascription),
    Extern(Extern),
}
