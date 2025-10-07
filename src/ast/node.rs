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
    File,
    Path,
    PathSegment,
    Param,
    Params,
    Field,
    GenericParameters,
    GenericParameter,

    /* patterns */
    WildcardPattern,
    BindingPattern,

    /* expressions */
    IntExpr,
    FloatExpr,
    StrExpr,
    TrueExpr,
    FalseExpr,
    LetExpr,
    PathExpr,
    CallExpr,
    BinaryExpr,
    BlockExpr,
    ParenExpr,

    /* types */
    NatType,
    IntType,
    NumType,
    StrType,
    BoolType,
    NoneType,
    NeverType,
    PathType,
    FnType,
    RecordType,
    UnionType,
    GenericType,
    ParenType,

    /* items */
    FnItem,
    AliasItem,
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

    pub fn nodes(&self) -> impl Iterator<Item = &Self> {
        self.children.iter().filter_map(|c| match c {
            Child::Token(_, _) => None,
            Child::Node(node) => Some(node),
        })
    }

    pub fn nodes_of(&self, kind: Kind) -> impl Iterator<Item = &Self> {
        self.nodes().filter(move |n| n.kind == kind)
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

    pub fn string(&self, i: usize) -> Option<&str> {
        let child = self.semantic_children().nth(i).unwrap();

        match child {
            Child::Token(_, s) => Some(s),
            Child::Node(_) => None,
        }
    }

    pub fn span(&self, i: usize) -> Span {
        let mut offset = self.span.start;

        self.children
            .iter()
            .filter_map(|c| {
                let span = Span {
                    start:  offset,
                    end:    offset + c.input_len(),
                    source: self.span.source,
                };

                offset += c.input_len();

                c.is_semantic().then_some(span)
            })
            .nth(i)
            .unwrap()
    }
}

impl Child {
    pub fn is_semantic(&self) -> bool {
        match self {
            Child::Token(token, _) => token.is_semantic(),
            Child::Node(_) => true,
        }
    }

    pub fn input_len(&self) -> u32 {
        match self {
            Child::Token(_, s) => s.len() as u32,
            Child::Node(node) => node.span.len(),
        }
    }
}
