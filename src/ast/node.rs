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

    /* misc */
    Path,
    PathSegment,
    Param,
    Params,
    Field,

    /* expressions */
    IntExpr,
    FloatExpr,
    StrExpr,
    TrueExpr,
    FalseExpr,
    LetExpr,
    PathExpr,
    BlockExpr,
    ParenExpr,

    /* types */
    IntType,
    FloatType,
    StrType,
    BoolType,
    PathType,
    FnType,
    RecordType,
    UnionType,
    GenericType,

    /* items */
    FnItem,
    TypeItem,
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
        let child = self.semantic_children().nth(i).unwrap();

        match child {
            Child::Token(_, s) => panic!("expected child at [{i}], but found token `{s}`"),
            Child::Node(node) => node,
        }
    }

    pub fn token(&self, i: usize) -> Option<Token> {
        let child = self.semantic_children().nth(i).unwrap();

        match child {
            Child::Token(token, _) => Some(*token),
            Child::Node(_) => None,
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
