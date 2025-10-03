#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Token {
    /* special */
    Error,
    Comment,

    /* whitespace */
    Newline,
    Whitespace,

    /* varying length */
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
