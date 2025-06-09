use std::sync::Arc;

use crate::diagnostic::{Diagnostic, Span};

use super::Token;

#[derive(Clone, Debug, PartialEq)]
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
                Token::Whitespace => index += 1,
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
                Token::Whitespace => continue,
                Token::Eof => return *span,
                _ => return *span,
            }
        }
    }

    pub fn is_whitespace(&self) -> bool {
        let (token, _) = &self.tokens[self.current];
        matches!(token, Token::Whitespace)
    }

    pub fn expect(&mut self, expected: &Token) -> Result<Span, Diagnostic> {
        let (token, span) = self.peek();

        if token == *expected {
            self.consume();
            Ok(span)
        } else {
            let message = format!("expected token: `{}`", expected);
            let diagnostic = Diagnostic::error(message).with_span(span);
            Err(diagnostic)
        }
    }
}
