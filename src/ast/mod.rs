use std::{collections::HashMap, fmt, ops::Deref};

use crate::diagnostic::Span;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Module {
    pub files: HashMap<String, File>,
    pub modules: HashMap<String, Module>,
}

impl Module {
    pub fn new() -> Self {
        Self::default()
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct File {
    pub items: Vec<Item>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ExprKind {
    Int(i64),
    Bool(bool),
    String(String),
    Format(Vec<Expr>),
    Path(Path),
    Let(Pattern, Box<Expr>),
    Record(Path, Vec<(String, Expr, Span)>),
    With(Box<Expr>, Vec<(String, Expr, Span)>),
    List(Vec<Expr>, Option<Box<Expr>>),
    Tuple(Vec<Expr>),
    Lambda(Vec<Pattern>, Box<Expr>),
    Binary(BinOp, Span, Box<Expr>, Box<Expr>),
    Try(Box<Expr>),
    Call(Box<Expr>, Box<Expr>),
    Field(Box<Expr>, String, Span),
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
    Int(i64),
    String(String),
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
    Path(Path, Vec<Type>),
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
pub struct Path {
    pub segments: Vec<String>,
    pub span: Span,
}

impl Path {
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

impl fmt::Display for Path {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.segments.join("::").fmt(f)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Function {
    pub name: Path,
    pub params: Vec<Pattern>,
    pub body: Option<Expr>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Newtype {
    pub name: Path,
    pub generics: Vec<(String, Span)>,
    pub kind: NewtypeKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum NewtypeKind {
    Union(Vec<Variant>),
    Record(Vec<Field>),
    Alias(Type),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Variant {
    pub name: Path,
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
    pub name: Path,
    pub ty: Type,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Extern {
    pub name: Path,
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
