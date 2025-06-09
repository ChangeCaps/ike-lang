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

use crate::{
    ast::Path,
    diagnostic::{Diagnostic, Span},
};

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

fn parse_path(tokens: &mut TokenStream) -> Result<Path, Diagnostic> {
    let mut segments = Vec::new();
    let mut generics = Vec::new();

    let (first, mut span) = parse_ident(tokens)?;
    segments.push(first);

    while tokens.is(&Token::ColonColon) && !tokens.is_whitespace() {
        tokens.consume();

        let (segment, segment_span) = parse_ident(tokens)?;

        segments.push(segment);
        span = span.join(segment_span);
    }

    if tokens.is(&Token::Lt) && !tokens.is_whitespace() {
        tokens.consume();

        while !tokens.is(&Token::Gt) {
            let ty = parse_type(tokens)?;
            generics.push(ty);

            if tokens.is(&Token::Gt) {
                break;
            }

            tokens.expect(&Token::Comma)?;
        }

        let generics_span = tokens.expect(&Token::Gt)?;
        span = span.join(generics_span);
    }

    Ok(Path {
        segments,
        generics,
        span,
    })
}

fn consume_newlines(tokens: &mut TokenStream) {
    while tokens.is(&Token::Newline) {
        tokens.consume();
    }
}
