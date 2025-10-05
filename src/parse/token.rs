use std::fmt::{self, write};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Token {
    /* special */
    Error,
    Comment,
    Eof,

    /* whitespace */
    Newline,
    Whitespace,

    /* variable length tokens */
    Ident,
    Integer,
    String,

    /* keywords */
    Let,
    Fn,
    Type,
    Int,
    Float,
    Bool,

    /* two character symbols */
    DotDot,
    EqEq,

    /* one character symbols */
    Dot,
    Eq,
}

impl Token {
    /// Checks if the token has semantic meaning.
    ///
    /// Returns false for [`Token::Whitespace`] and [`Token::Comment`].
    pub fn is_semantic(self) -> bool {
        !matches!(self, Token::Whitespace | Token::Comment)
    }
}

impl fmt::Display for Token {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Token::Error => write!(f, "error"),
            Token::Comment => write!(f, "comment"),
            Token::Eof => write!(f, "end of file"),

            /* whitespace */
            Token::Newline => write!(f, "newline"),
            Token::Whitespace => write!(f, "whitespace"),

            /* variable length tokens */
            Token::Ident => write!(f, "identifier"),
            Token::Integer => write!(f, "integer"),
            Token::String => write!(f, "string"),

            /* keywords */
            Token::Let => write!(f, "let"),
            Token::Fn => write!(f, "fn"),
            Token::Type => write!(f, "type"),
            Token::Int => write!(f, "int"),
            Token::Float => write!(f, "float"),
            Token::Bool => write!(f, "bool"),

            /* two character symbols */
            Token::DotDot => write!(f, ".."),
            Token::EqEq => write!(f, "=="),

            /* one character symbols */
            Token::Dot => write!(f, "."),
            Token::Eq => write!(f, "="),
        }
    }
}
