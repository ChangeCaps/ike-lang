use std::{fmt, str::FromStr};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Token {
    Ident(String),
    String(String),
    Integer(i64),

    /* special */
    Whitespace,
    Newline,
    Eof,

    /* keywords */
    Bool,   // 'bool'
    False,  // 'false'
    Fn,     // 'fn'
    Import, // 'import'
    Let,    // 'let'
    True,   // 'true'
    Type,   // 'type'
    Int,    // 'int'
    Str,    // 'str'
    Extern, // 'extern'
    Match,  // 'match'

    /* two-character symbols */
    DotDot,     // '..'
    RArrow,     // '->'
    LArrow,     // '<-'
    ColonColon, // '::'
    AmpAmp,     // '&&'
    PipePipe,   // '||'
    EqEq,       // '=='
    NotEq,      // '!='
    LtEq,       // '<='
    GtEq,       // '>='
    LtPipe,     // '<|'
    PipeGt,     // '|>'

    /* one-character symbols */
    Semi,      // ';'
    Colon,     // ':'
    Comma,     // ','
    Dot,       // '.'
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
            Token::Ident(s) => write!(f, "{}", s),
            Token::String(s) => write!(f, "\"{}\"", s),
            Token::Integer(i) => write!(f, "{}", i),

            Token::Whitespace => write!(f, "whitespace"),
            Token::Newline => write!(f, "newline"),
            Token::Eof => write!(f, "end of file"),

            /* keywords */
            Token::Bool => write!(f, "bool"),
            Token::False => write!(f, "false"),
            Token::Fn => write!(f, "fn"),
            Token::Import => write!(f, "import"),
            Token::Let => write!(f, "let"),
            Token::True => write!(f, "true"),
            Token::Type => write!(f, "type"),
            Token::Int => write!(f, "int"),
            Token::Str => write!(f, "str"),
            Token::Extern => write!(f, "extern"),
            Token::Match => write!(f, "match"),

            /* two-character symbols */
            Token::DotDot => write!(f, ".."),
            Token::RArrow => write!(f, "->"),
            Token::LArrow => write!(f, "<-"),
            Token::ColonColon => write!(f, "::"),
            Token::AmpAmp => write!(f, "&&"),
            Token::PipePipe => write!(f, "||"),
            Token::EqEq => write!(f, "=="),
            Token::NotEq => write!(f, "!="),
            Token::LtEq => write!(f, "<="),
            Token::GtEq => write!(f, ">="),
            Token::LtPipe => write!(f, "<|"),
            Token::PipeGt => write!(f, "|>"),

            /* one-character symbols */
            Token::Semi => write!(f, ";"),
            Token::Colon => write!(f, ":"),
            Token::Comma => write!(f, ","),
            Token::Dot => write!(f, "."),
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
            "bool" => Token::Bool,
            "false" => Token::False,
            "fn" => Token::Fn,
            "import" => Token::Import,
            "let" => Token::Let,
            "true" => Token::True,
            "type" => Token::Type,
            "int" => Token::Int,
            "str" => Token::Str,
            "extern" => Token::Extern,
            "match" => Token::Match,

            /* two-character symbols */
            ".." => Token::DotDot,
            "->" => Token::RArrow,
            "<-" => Token::LArrow,
            "::" => Token::ColonColon,
            "&&" => Token::AmpAmp,
            "||" => Token::PipePipe,
            "==" => Token::EqEq,
            "!=" => Token::NotEq,
            "<=" => Token::LtEq,
            ">=" => Token::GtEq,
            "<|" => Token::LtPipe,
            "|>" => Token::PipeGt,

            /* one-character symbols */
            ";" => Token::Semi,
            ":" => Token::Colon,
            "," => Token::Comma,
            "." => Token::Dot,
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
