use std::str::FromStr;

use crate::diagnostic::{Diagnostic, Emitter, Sid, Span};

use super::{Token, TokenStream};

struct Lexer<'a> {
    input: &'a str,
    offset: usize,
    source: Sid,
}

impl Lexer<'_> {
    fn remaining(&self) -> &str {
        &self.input[self.offset..]
    }

    fn peek(&self) -> Option<char> {
        self.remaining().chars().next()
    }

    fn advance(&mut self) -> Option<char> {
        let c = self.peek()?;
        self.offset += c.len_utf8();
        Some(c)
    }

    fn span_from(&self, start: usize) -> Span {
        Span::new(self.source, start as u32, self.offset as u32)
    }
}

fn lex_whitespace(lexer: &mut Lexer) -> Token {
    while lexer.peek().is_some_and(|c| c.is_whitespace() && c != '\n') {
        lexer.advance();
    }

    Token::Whitespace
}

fn is_ident_start(c: char) -> bool {
    c.is_alphabetic() || c == '_'
}

fn is_ident_continue(c: char) -> bool {
    c.is_alphanumeric() || c == '_' || c == '-' || c == '\''
}

fn lex_ident(lexer: &mut Lexer) -> Token {
    let mut ident = String::new();

    while let Some(c) = lexer.peek() {
        if is_ident_continue(c) {
            ident.push(c);
            lexer.advance();
        } else {
            break;
        }
    }

    match Token::from_str(&ident) {
        Ok(token) => token,
        Err(()) => Token::Ident(ident),
    }
}

fn lex_string(lexer: &mut Lexer) -> Token {
    lexer.advance(); // consume the opening quote

    let mut string = String::new();

    while let Some(c) = lexer.peek() {
        if c == '"' {
            lexer.advance();
            break;
        } else if lexer.remaining().starts_with("\\\\") {
            string.push('\\');
            string.push('\\');
            lexer.advance();
            lexer.advance();
        } else if lexer.remaining().starts_with("\\\"") {
            string.push('\\');
            string.push('"');
            lexer.advance();
            lexer.advance();
        } else {
            string.push(c);
            lexer.advance();
        }
    }

    Token::String(string)
}

fn lex_integer(lexer: &mut Lexer) -> Token {
    let mut number = String::new();

    while let Some(c) = lexer.peek() {
        if c.is_ascii_digit() {
            number.push(c);
            lexer.advance();
        } else {
            break;
        }
    }

    Token::Integer(number.parse().unwrap())
}

pub fn tokenize(
    input: &str,
    source: Sid,
    emitter: &mut dyn Emitter,
) -> Result<TokenStream, TokenStream> {
    let mut lexer = Lexer {
        input,
        offset: 0,
        source,
    };

    let mut tokens = Vec::new();
    let mut is_error = false;

    while let Some(c) = lexer.peek() {
        let start = lexer.offset;

        if c == '\n' {
            lexer.advance();
            tokens.push((Token::Newline, lexer.span_from(start)));
            continue;
        }

        if c.is_whitespace() {
            let token = lex_whitespace(&mut lexer);
            tokens.push((token, lexer.span_from(start)));
            continue;
        }

        if lexer.remaining().starts_with("//") {
            // single-line comment
            while let Some(c) = lexer.peek() {
                if c == '\n' {
                    break;
                }

                lexer.advance();
            }

            let comment = &lexer.input[start + 2..lexer.offset];
            let span = lexer.span_from(start);

            tokens.push((Token::Comment(comment.to_string()), span));

            continue;
        }

        if c.is_ascii_digit() {
            let token = lex_integer(&mut lexer);
            tokens.push((token, lexer.span_from(start)));
            continue;
        }

        if c == '"' {
            let token = lex_string(&mut lexer);
            tokens.push((token, lexer.span_from(start)));
            continue;
        }

        if c != 'f' && c != 'o' {
            // handle two-character symbols
            if lexer.remaining().len() >= 2
                && let Ok(token) = Token::from_str(&lexer.remaining()[..2])
            {
                lexer.advance();
                lexer.advance();
                tokens.push((token, lexer.span_from(start)));
                continue;
            }

            // handle one-character symbols
            if let Ok(token) = Token::from_str(&c.to_string()) {
                lexer.advance();
                tokens.push((token, lexer.span_from(start)));
                continue;
            }
        }

        if is_ident_start(c) {
            let token = lex_ident(&mut lexer);
            tokens.push((token, lexer.span_from(start)));
            continue;
        }

        let span = lexer.span_from(start);
        let message = format!("Unexpected character: '{c}'");
        let diagnostic = Diagnostic::error(message).with_span(span);
        emitter.emit(diagnostic);

        is_error = true;
        break;
    }

    let eof_span = lexer.span_from(lexer.offset);
    tokens.push((Token::Eof, eof_span));

    match is_error {
        false => Ok(TokenStream::new(tokens)),
        true => Err(TokenStream::new(tokens)),
    }
}
