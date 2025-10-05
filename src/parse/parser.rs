use crate::{
    ast,
    diagnostic::{self, Diagnostic, SourceId, Span},
    parse::{Token, TokenStream},
};

pub struct Parser<'a> {
    emitter: &'a mut dyn diagnostic::Emitter,
    source:  SourceId,
    tokens:  TokenStream<'a>,
    offset:  usize,
    peek:    Vec<(Token, Span)>,
    stack:   Vec<ast::Node>,
}

impl<'a> Parser<'a> {
    /// Create a new [`Parser`].
    pub fn new(emitter: &'a mut dyn diagnostic::Emitter, input: &'a str, source: SourceId) -> Self {
        Self {
            emitter,
            source,
            tokens: TokenStream::new(input),
            offset: 0,
            peek: Vec::new(),
            stack: Vec::new(),
        }
    }

    fn next_token(&mut self) -> (Token, Span) {
        match self.tokens.next() {
            None => {
                let span = Span {
                    source: self.source,
                    start:  self.offset as u32,
                    end:    self.offset as u32,
                };

                (Token::Eof, span)
            }

            Some((token, len)) => {
                let span = Span {
                    source: self.source,
                    start:  self.offset as u32,
                    end:    self.offset as u32 + len as u32,
                };

                self.offset += len;

                (token, span)
            }
        }
    }

    pub fn span(&mut self, i: usize) -> Span {
        self.peek(i);
        self.peek[i].1
    }

    /// Peek the [`Token`] at `i`.
    pub fn peek(&mut self, mut i: usize) -> Token {
        let mut j = 0;

        loop {
            match self.peek.get(j) {
                Some((token, _)) => {
                    j += 1;

                    if matches!(token, Token::Whitespace | Token::Comment) {
                        continue;
                    }

                    if i == 0 {
                        return *token;
                    }

                    i -= 1;
                }

                None => {
                    let peek = self.next_token();
                    self.peek.push(peek);
                }
            }
        }
    }

    pub fn is(&mut self, token: Token) -> bool {
        self.peek(0) == token
    }

    /// Advance the parser by `n` tokens and return the combined span.
    pub fn advance(&mut self, mut n: usize) -> Span {
        assert!(n > 0);
        assert!(!self.stack.is_empty());

        self.peek(n - 1);
        let node = self.stack.last_mut().unwrap();

        let &(_, mut combined_span) = self.peek.last().unwrap();

        while n > 0 {
            let (token, span) = self.peek.remove(0);
            combined_span = combined_span.join(span);

            let s = &self.tokens.input()[span.start as usize..span.end as usize];
            node.children.push(ast::Child::Token(token, s.into()));

            if !matches!(token, Token::Whitespace | Token::Comment) {
                n -= 1;
            }
        }

        combined_span
    }

    /// Open a new [`ast::Node`], all subsequent calls to [`Self::advance`], will append tokens to
    /// this node until [`Self::open`] or [`Self::close`] is called.
    pub fn open(&mut self, kind: ast::Kind) {
        // ensure at least one element in `self.peek`
        self.peek(1);
        let (_, span) = self.peek[0];

        let node = ast::Node {
            kind,
            span: Span {
                source: self.source,
                start:  span.start,
                end:    span.start,
            },
            children: Vec::new(),
        };

        self.stack.push(node);
    }

    pub fn open_before(&mut self, kind: ast::Kind) {
        assert!(!self.stack.is_empty());

        let node = self.stack.last_mut().unwrap();
        let Some(ast::Child::Node(child)) = node.children.pop() else {
            panic!();
        };

        let node = ast::Node {
            kind,
            span: child.span,
            children: vec![ast::Child::Node(child)],
        };

        self.stack.push(node);
    }

    /// Close the current [`ast::Node`] opened with [`Self::open`], and append it the [`ast::Node`]
    /// below it in the stack.
    pub fn close(&mut self) {
        assert!(self.stack.len() >= 2);

        let node = self.stack.pop().unwrap();

        self.stack
            .last_mut()
            .unwrap()
            .children
            .push(ast::Child::Node(node));
    }

    pub fn finish(mut self) -> ast::Node {
        assert_eq!(self.stack.len(), 1);
        assert_eq!(self.peek(0), Token::Eof);

        self.stack.pop().unwrap()
    }

    pub fn expect(&mut self, token: Token) -> bool {
        if self.peek(0) == token {
            self.advance(1);

            true
        } else {
            self.open(ast::Kind::Error);
            self.close();

            let span = self.span(0);
            let diagnostic = Diagnostic::error(format!(
                "expected token `{token}`, but found `{actual}`",
                actual = self.peek(0),
            ))
            .label(span, "here");

            self.emit(diagnostic);

            false
        }
    }

    pub fn error(&mut self, diagnostic: Diagnostic) {
        self.open(ast::Kind::Error);
        self.advance(1);
        self.close();

        self.emit(diagnostic);
    }

    pub fn emit(&mut self, diagnostic: Diagnostic) {
        self.emitter.emit(diagnostic);
    }
}

// WARNING: here be dragons
#[cfg(test)]
macro_rules! test_parser {
    ($parser:path : $input:expr => $($tt:tt)*) => {
        let mut emitter = Vec::new();
        let mut parser = $crate::parse::Parser::new(
            &mut emitter,
            $input, // input
            $crate::diagnostic::SourceId::DUMMY,
        );

        parser.open($crate::ast::Kind::Error);

        $parser(&mut parser);

        let node = parser.finish();

        $crate::parse::test_parser!(@check node[0] $($tt)*);
    };

    (@check $node:ident[$n:expr] $kind:path { $($content:tt)* } $(, $($rest:tt)* )?) => {
        let node = $node.node($n);

        assert_eq!(node.kind, $kind);

        $crate::parse::test_parser!(@check node[0] $($content)*);

        $(
            $crate::parse::test_parser!(@check $node[$n + 1] $($rest)*);
        )?
    };

    (@check $node:ident[$n:expr] $token:path $(, $($rest:tt)* )?) => {
        let token = $node.token($n).unwrap();

        assert_eq!(token, $token);

        $(
            $crate::parse::test_parser!(@check $node[$n + 1] $($rest)*);
        )?
    };

    (@check $node:ident[$n:expr]) => {
        assert_eq!(
            $node.semantic_children().count(), $n,
            "ast node has the wrong number of semantically relevant children",
        );
    };
}

#[cfg(test)]
pub(crate) use test_parser;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn peek() {
        let mut emitter = diagnostic::PanicEmitter;
        let mut parser = Parser::new(&mut emitter, "let = x", SourceId::DUMMY);

        assert_eq!(parser.peek(0), Token::Let);
        assert_eq!(parser.peek(1), Token::Eq);
        assert_eq!(parser.peek(2), Token::Ident);
        assert_eq!(parser.peek(3), Token::Eof);
    }

    #[test]
    fn advance() {
        let mut emitter = diagnostic::PanicEmitter;
        let mut parser = Parser::new(&mut emitter, "let = x", SourceId::DUMMY);

        parser.open(ast::Kind::LetExpr);

        assert_eq!(parser.peek(0), Token::Let);

        let span = parser.advance(2);

        assert_eq!(span.source, SourceId::DUMMY);
        assert_eq!(span.start, 0);
        assert_eq!(span.end, 5);

        assert_eq!(parser.peek(0), Token::Ident);

        let span = parser.advance(2);

        assert_eq!(span.source, SourceId::DUMMY);
        assert_eq!(span.start, 5);
        assert_eq!(span.end, 7);

        assert_eq!(parser.peek(0), Token::Eof);

        let node = parser.finish();

        assert_eq!(node.kind, ast::Kind::LetExpr);

        assert_eq!(
            node.children[0],
            ast::Child::Token(Token::Let, String::from("let")),
        );
        assert_eq!(
            node.children[1],
            ast::Child::Token(Token::Whitespace, String::from(" ")),
        );
        assert_eq!(
            node.children[2],
            ast::Child::Token(Token::Eq, String::from("=")),
        );
        assert_eq!(
            node.children[3],
            ast::Child::Token(Token::Whitespace, String::from(" ")),
        );
        assert_eq!(
            node.children[4],
            ast::Child::Token(Token::Ident, String::from("x")),
        );
    }
}
