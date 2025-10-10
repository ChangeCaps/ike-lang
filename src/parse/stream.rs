use crate::parse::Token;

#[derive(Clone, Debug)]
pub struct TokenStream<'a> {
    input:  &'a str,
    offset: usize,
}

impl<'a> TokenStream<'a> {
    pub fn new(input: &'a str) -> Self {
        Self { input, offset: 0 }
    }

    pub fn input(&self) -> &'a str {
        self.input
    }

    fn remaining(&self) -> &'a str {
        &self.input[self.offset..]
    }

    fn advance(&mut self, n: usize) {
        self.offset += self
            .remaining()
            .chars()
            .take(n)
            .map(char::len_utf8)
            .sum::<usize>();
    }

    fn advance_while(&mut self, f: impl Fn(char) -> bool) -> bool {
        let length = self
            .remaining()
            .chars()
            .take_while(|&c| f(c))
            .map(char::len_utf8)
            .sum::<usize>();

        self.offset += length;

        length > 0
    }

    fn whitespace(&mut self) -> bool {
        self.advance_while(char::is_whitespace)
    }

    fn two_character_symbol(&mut self) -> Option<Token> {
        if self.remaining().len() < 2 {
            return None;
        }

        let token = match &self.remaining()[..2] {
            "::" => Token::ColonColon,
            ".." => Token::DotDot,
            "==" => Token::EqEq,
            "!=" => Token::BangEq,
            "<=" => Token::LtEq,
            ">=" => Token::GtEq,
            "->" => Token::Arrow,

            _ => return None,
        };

        self.advance(2);

        Some(token)
    }

    fn one_character_symbol(&mut self) -> Option<Token> {
        if self.remaining().is_empty() {
            return None;
        }

        let token = match &self.remaining()[..1] {
            "(" => Token::LParen,
            ")" => Token::RParen,
            "{" => Token::LBrace,
            "}" => Token::RBrace,
            "[" => Token::LBracket,
            "]" => Token::RBracket,
            "'" => Token::Quote,
            ":" => Token::Colon,
            ";" => Token::Semi,
            "," => Token::Comma,
            "." => Token::Dot,
            "|" => Token::Pipe,
            "!" => Token::Bang,
            "#" => Token::Pound,
            "+" => Token::Plus,
            "-" => Token::Minus,
            "*" => Token::Star,
            "/" => Token::Slash,
            "%" => Token::Percent,
            "=" => Token::Eq,
            "<" => Token::Lt,
            ">" => Token::Gt,

            _ => return None,
        };

        self.advance(1);

        Some(token)
    }

    fn ident(&mut self) -> Token {
        let start = self.offset;
        self.advance_while(Self::is_ident_continue);
        let end = self.offset;

        match &self.input[start..end] {
            "alias" => Token::Alias,
            "bool" => Token::Bool,
            "false" => Token::False,
            "fn" => Token::Fn,
            "int" => Token::Int,
            "let" => Token::Let,
            "nat" => Token::Nat,
            "none" => Token::None,
            "num" => Token::Num,
            "str" => Token::Str,
            "true" => Token::True,
            "type" => Token::Type,

            _ => Token::Ident,
        }
    }

    fn is_ident_start(c: char) -> bool {
        c.is_alphabetic() || c == '_'
    }

    fn is_ident_continue(c: char) -> bool {
        c.is_alphanumeric() || c == '_' || c == '-'
    }

    fn integer(&mut self) -> bool {
        self.advance_while(|c| c.is_ascii_digit())
    }

    fn token(&mut self) -> Option<Token> {
        let c = self.remaining().chars().next()?;

        if self.remaining() == "//" {
            self.advance_while(|c| c != '\n');
            return Some(Token::Comment);
        }

        if c == '\n' {
            self.advance(1);
            return Some(Token::Newline);
        }

        if self.whitespace() {
            return Some(Token::Whitespace);
        }

        if let Some(token) = self.two_character_symbol() {
            return Some(token);
        }

        if let Some(token) = self.one_character_symbol() {
            return Some(token);
        }

        if Self::is_ident_start(c) {
            return Some(self.ident());
        }

        if self.integer() {
            return Some(Token::Integer);
        }

        self.advance(1);

        Some(Token::Error)
    }
}

impl Iterator for TokenStream<'_> {
    type Item = (Token, usize);

    fn next(&mut self) -> Option<Self::Item> {
        let start = self.offset;

        let token = self.token()?;
        let length = self.offset - start;

        Some((token, length))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    macro_rules! test_ts {
        ($( $input:literal => [$($token:expr),* $(,)?] ),* $(,)? ) => {
            $({
                let mut stream = TokenStream::new($input);

                $(assert_eq!($token, stream.next().unwrap().0);)*
            })*
        };
    }

    #[test]
    fn code() {
        test_ts! {
            "let x = 2\n" => [
                Token::Let,
                Token::Whitespace,
                Token::Ident,
                Token::Whitespace,
                Token::Eq,
                Token::Whitespace,
                Token::Integer,
                Token::Newline,
            ],
        }
    }

    #[test]
    fn ident() {
        test_ts! {
            "hello" => [Token::Ident],
        }
    }

    #[test]
    fn symbols() {
        test_ts! {
            "..." => [Token::DotDot, Token::Dot],
        }
    }
}
