use std::{fmt, sync::Arc};

use crate::diagnostic::{Diagnostic, Span};

use super::Token;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TokenStream {
    tokens: Arc<[(Token, Span)]>,
    current: usize,
}

impl TokenStream {
    pub fn new(tokens: Vec<(Token, Span)>) -> Self {
        Self {
            tokens: Arc::from(tokens),
            current: 0,
        }
    }

    pub fn peek_nth(&self, mut n: usize) -> (Token, Span) {
        let mut index = self.current;

        loop {
            let (token, span) = &self.tokens[index];

            match token {
                Token::Comment(_) | Token::Whitespace => index += 1,
                Token::Eof => return (token.clone(), *span),
                _ if n == 0 => return (token.clone(), *span),
                _ => {
                    index += 1;
                    n -= 1;
                }
            }
        }
    }

    pub fn peek(&self) -> (Token, Span) {
        self.peek_nth(0)
    }

    pub fn nth_is(&self, n: usize, token: &Token) -> bool {
        let (peeked_token, _) = self.peek_nth(n);
        peeked_token == *token
    }

    pub fn is(&self, token: &Token) -> bool {
        self.nth_is(0, token)
    }

    pub fn consume(&mut self) -> Span {
        loop {
            let (token, span) = &self.tokens[self.current];

            self.current += 1;

            match token {
                Token::Comment(_) | Token::Whitespace => continue,
                Token::Eof => return *span,
                _ => return *span,
            }
        }
    }

    pub fn is_whitespace(&self) -> bool {
        let (token, _) = &self.tokens[self.current];
        matches!(token, Token::Whitespace)
    }

    pub fn expect<T>(&mut self, expected: &T) -> Result<Span, Diagnostic>
    where
        Token: PartialEq<T>,
        T: ?Sized + fmt::Display,
    {
        let (token, span) = self.peek();

        if token == *expected {
            self.consume();
            Ok(span)
        } else {
            let message = format!("expected token: `{expected}`");
            let diagnostic = Diagnostic::error(message).with_span(span);
            Err(diagnostic)
        }
    }
}

impl<'a> IntoIterator for &'a TokenStream {
    type Item = &'a (Token, Span);
    type IntoIter = std::slice::Iter<'a, (Token, Span)>;

    fn into_iter(self) -> Self::IntoIter {
        self.tokens[self.current..].iter()
    }
}

impl PartialEq<str> for Token {
    fn eq(&self, other: &str) -> bool {
        match self {
            Token::Ident(ident) => ident == other,
            _ => false,
        }
    }
}
