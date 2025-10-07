use std::fmt;

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
    Alias,
    Bool,
    False,
    Fn,
    Int,
    Let,
    Nat,
    None,
    Num,
    Str,
    True,
    Type,

    /* two character symbols */
    ColonColon,
    DotDot,
    EqEq,
    Arrow,

    /* one character symbols */
    LParen,
    RParen,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Quote,
    Colon,
    Semi,
    Comma,
    Dot,
    Pipe,
    Bang,
    Eq,
    Lt,
    Gt,
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
            Token::Alias => write!(f, "alias"),
            Token::Bool => write!(f, "bool"),
            Token::False => write!(f, "false"),
            Token::Fn => write!(f, "fn"),
            Token::Int => write!(f, "int"),
            Token::Let => write!(f, "let"),
            Token::Nat => write!(f, "nat"),
            Token::None => write!(f, "none"),
            Token::Num => write!(f, "num"),
            Token::Str => write!(f, "str"),
            Token::True => write!(f, "true"),
            Token::Type => write!(f, "type"),

            /* two character symbols */
            Token::ColonColon => write!(f, "::"),
            Token::DotDot => write!(f, ".."),
            Token::EqEq => write!(f, "=="),
            Token::Arrow => write!(f, "->"),

            /* one character symbols */
            Token::LParen => write!(f, "("),
            Token::RParen => write!(f, ")"),
            Token::LBrace => write!(f, "{{"),
            Token::RBrace => write!(f, "}}"),
            Token::LBracket => write!(f, "["),
            Token::RBracket => write!(f, "]"),
            Token::Quote => write!(f, "'"),
            Token::Colon => write!(f, ":"),
            Token::Semi => write!(f, ";"),
            Token::Comma => write!(f, ","),
            Token::Dot => write!(f, "."),
            Token::Pipe => write!(f, "|"),
            Token::Bang => write!(f, "!"),
            Token::Eq => write!(f, "="),
            Token::Lt => write!(f, "<"),
            Token::Gt => write!(f, ">"),
        }
    }
}
