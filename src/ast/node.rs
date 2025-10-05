use crate::{diagnostic::Span, parse::Token};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Node {
    pub kind:     Kind,
    pub span:     Span,
    pub children: Vec<Child>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Kind {
    Error,

    Path,
    PathSegment,

    /* expressions */
    IntExpr,
    FloatExpr,
    StrExpr,
    BoolExpr,
    LetExpr,

    /* types */
    IntType,
    FloatType,
    StrType,
    BoolType,
    RecordType,
    UnionType,

    /* declarations */
    FnDecl,
    TypeDecl,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Child {
    Token(Token, String),
    Node(Node),
}

impl Node {
    pub fn semantic_children(&self) -> impl DoubleEndedIterator<Item = &Child> {
        self.children.iter().filter(|c| c.is_semantic())
    }

    pub fn node(&self, i: usize) -> &Node {
        let child = self.semantic_children().nth(0).unwrap();

        match child {
            Child::Token(_, s) => panic!("expected child at [{i}], but found token `{s}`"),
            Child::Node(node) => node,
        }
    }
}

impl Child {
    pub fn is_semantic(&self) -> bool {
        match self {
            Child::Token(token, _) => token.is_semantic(),
            Child::Node(_) => true,
        }
    }
}
