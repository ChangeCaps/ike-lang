use std::{fmt, str::FromStr};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Token {
    Ident(String),
    String(String),
    Integer(i64),

    /* special */
    Comment(String),
    Whitespace,
    Newline,
    Eof,

    /* keywords */
    And,   // 'and'
    Bool,  // 'bool'
    False, // 'false'
    Let,   // 'let'
    True,  // 'true'
    Try,   // 'try'
    Int,   // 'int'
    Or,    // 'or'
    Str,   // 'str'
    Match, // 'match'
    With,  // 'with'

    /* two-character symbols */
    DotDot,     // '..'
    RArrow,     // '->'
    LArrow,     // '<-'
    ColonColon, // '::'
    EqEq,       // '=='
    NotEq,      // '!='
    LtEq,       // '<='
    GtEq,       // '>='
    LtPipe,     // '<|'
    PipeGt,     // '|>'
    LtLt,       // '<<'
    GtGt,       // '>>'

    /* one-character symbols */
    Semi,      // ';'
    Colon,     // ':'
    Comma,     // ','
    Dot,       // '.'
    Pound,     // '#'
    Under,     // '_'
    Plus,      // '+'
    Minus,     // '-'
    Star,      // '*'
    Slash,     // '/'
    Backslash, // '\'
    Percent,   // '%'
    Amp,       // '&'
    Pipe,      // '|'
    Caret,     // '^'
    Bang,      // '!'
    Question,  // '?'
    Quote,     // '\''
    Eq,        // '='
    Tilde,     // '~'
    Lt,        // '<'
    Gt,        // '>'
    LParen,    // '('
    RParen,    // ')'
    LBrace,    // '{'
    RBrace,    // '}'
    LBracket,  // '['
    RBracket,  // ']'
}

impl fmt::Display for Token {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Token::Ident(s) => write!(f, "{s}"),
            Token::String(s) => write!(f, "\"{s}\""),
            Token::Integer(i) => write!(f, "{i}"),

            Token::Comment(comment) => write!(f, "//{comment}"),
            Token::Whitespace => write!(f, "whitespace"),
            Token::Newline => write!(f, "newline"),
            Token::Eof => write!(f, "end of file"),

            /* keywords */
            Token::And => write!(f, "and"),
            Token::Bool => write!(f, "bool"),
            Token::False => write!(f, "false"),
            Token::Let => write!(f, "let"),
            Token::True => write!(f, "true"),
            Token::Try => write!(f, "try"),
            Token::Int => write!(f, "int"),
            Token::Or => write!(f, "or"),
            Token::Str => write!(f, "str"),
            Token::Match => write!(f, "match"),
            Token::With => write!(f, "with"),

            /* two-character symbols */
            Token::DotDot => write!(f, ".."),
            Token::RArrow => write!(f, "->"),
            Token::LArrow => write!(f, "<-"),
            Token::ColonColon => write!(f, "::"),
            Token::EqEq => write!(f, "=="),
            Token::NotEq => write!(f, "!="),
            Token::LtEq => write!(f, "<="),
            Token::GtEq => write!(f, ">="),
            Token::LtPipe => write!(f, "<|"),
            Token::PipeGt => write!(f, "|>"),
            Token::LtLt => write!(f, "<<"),
            Token::GtGt => write!(f, ">>"),

            /* one-character symbols */
            Token::Semi => write!(f, ";"),
            Token::Colon => write!(f, ":"),
            Token::Comma => write!(f, ","),
            Token::Dot => write!(f, "."),
            Token::Pound => write!(f, "#"),
            Token::Under => write!(f, "_"),
            Token::Plus => write!(f, "+"),
            Token::Minus => write!(f, "-"),
            Token::Star => write!(f, "*"),
            Token::Slash => write!(f, "/"),
            Token::Backslash => write!(f, "\\"),
            Token::Percent => write!(f, "%"),
            Token::Amp => write!(f, "&"),
            Token::Pipe => write!(f, "|"),
            Token::Caret => write!(f, "^"),
            Token::Bang => write!(f, "!"),
            Token::Question => write!(f, "?"),
            Token::Quote => write!(f, "'"),
            Token::Eq => write!(f, "="),
            Token::Tilde => write!(f, "~"),
            Token::Lt => write!(f, "<"),
            Token::Gt => write!(f, ">"),
            Token::LParen => write!(f, "("),
            Token::RParen => write!(f, ")"),
            Token::LBrace => write!(f, "{{"),
            Token::RBrace => write!(f, "}}"),
            Token::LBracket => write!(f, "["),
            Token::RBracket => write!(f, "]"),
        }
    }
}

impl FromStr for Token {
    type Err = ();

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(match s {
            /* keywords */
            "and" => Token::And,
            "bool" => Token::Bool,
            "false" => Token::False,
            "let" => Token::Let,
            "true" => Token::True,
            "try" => Token::Try,
            "int" => Token::Int,
            "or" => Token::Or,
            "str" => Token::Str,
            "match" => Token::Match,
            "with" => Token::With,

            /* two-character symbols */
            ".." => Token::DotDot,
            "->" => Token::RArrow,
            "<-" => Token::LArrow,
            "::" => Token::ColonColon,
            "==" => Token::EqEq,
            "!=" => Token::NotEq,
            "<=" => Token::LtEq,
            ">=" => Token::GtEq,
            "<|" => Token::LtPipe,
            "|>" => Token::PipeGt,
            "<<" => Token::LtLt,
            ">>" => Token::GtGt,

            /* one-character symbols */
            ";" => Token::Semi,
            ":" => Token::Colon,
            "," => Token::Comma,
            "." => Token::Dot,
            "#" => Token::Pound,
            "_" => Token::Under,
            "+" => Token::Plus,
            "-" => Token::Minus,
            "*" => Token::Star,
            "/" => Token::Slash,
            "\\" => Token::Backslash,
            "%" => Token::Percent,
            "&" => Token::Amp,
            "|" => Token::Pipe,
            "^" => Token::Caret,
            "!" => Token::Bang,
            "?" => Token::Question,
            "'" => Token::Quote,
            "=" => Token::Eq,
            "~" => Token::Tilde,
            "<" => Token::Lt,
            ">" => Token::Gt,
            "(" => Token::LParen,
            ")" => Token::RParen,
            "{" => Token::LBrace,
            "}" => Token::RBrace,
            "[" => Token::LBracket,
            "]" => Token::RBracket,

            _ => return Err(()),
        })
    }
}
