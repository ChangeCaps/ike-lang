mod expr;
mod lex;
mod module;
mod pattern;
mod stream;
mod token;
mod r#type;

pub use expr::*;
pub use lex::*;
pub use module::*;
pub use pattern::*;
pub use stream::*;
pub use token::*;
pub use r#type::*;

use crate::diagnostic::{Diagnostic, Span};

fn parse_ident(tokens: &mut TokenStream) -> Result<(String, Span), Diagnostic> {
    let (token, span) = tokens.peek();

    match token {
        Token::Ident(ident) => {
            tokens.consume();
            Ok((ident.clone(), span))
        }

        _ => {
            let diagnostic = Diagnostic::error("expected identifier").with_span(span);
            Err(diagnostic)
        }
    }
}

fn consume_newlines(tokens: &mut TokenStream) {
    while tokens.is(&Token::Newline) {
        tokens.consume();
    }
}
