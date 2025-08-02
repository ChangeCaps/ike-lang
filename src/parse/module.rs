use crate::{
    ast::{
        Ascription, Extern, Field, File, Function, Import, Item, Newtype, NewtypeKind, Path,
        Variant,
    },
    diagnostic::{Diagnostic, Emitter},
};

use super::{
    Token, TokenStream, consume_newlines, parse_block_expr, parse_expr, parse_ident,
    parse_irrefutable_pattern, parse_type,
};

pub fn parse_path(tokens: &mut TokenStream) -> Result<Path, Diagnostic> {
    let mut segments = Vec::new();

    let (first, mut span) = parse_ident(tokens)?;
    segments.push(first);

    while tokens.is(&Token::ColonColon) {
        tokens.consume();

        let (segment, segment_span) = parse_ident(tokens)?;
        segments.push(segment);
        span = span.join(segment_span);
    }

    Ok(Path { segments, span })
}

fn parse_import(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    let span = tokens.expect("import")?;

    let path = parse_path(tokens)?;
    let import = Import { path, span };

    Ok(Item::Import(import))
}

fn parse_fields(tokens: &mut TokenStream) -> Result<Vec<Field>, Diagnostic> {
    tokens.expect(&Token::LBrace)?;

    let mut fields = Vec::new();

    consume_newlines(tokens);

    while !tokens.is(&Token::RBrace) {
        let (name, span) = parse_ident(tokens)?;

        tokens.expect(&Token::Colon)?;

        let ty = parse_type(tokens)?;

        fields.push(Field { name, ty, span });

        if !(tokens.is(&Token::RBrace) || tokens.is(&Token::Newline)) {
            tokens.expect(&Token::Semi)?;
        }

        consume_newlines(tokens);
    }

    tokens.expect(&Token::RBrace)?;

    Ok(fields)
}

fn parse_variant(tokens: &mut TokenStream) -> Result<Variant, Diagnostic> {
    let name = parse_path(tokens)?;

    let ty = if tokens.is(&Token::Newline) || tokens.is(&Token::Pipe) {
        None
    } else {
        Some(parse_type(tokens)?)
    };

    let span = name.span;
    Ok(Variant { name, ty, span })
}

fn is_variant(tokens: &mut TokenStream) -> bool {
    let mut n = 0;

    while tokens.nth_is(n, &Token::Newline) {
        n += 1;
    }

    tokens.nth_is(n, &Token::Pipe)
}

fn parse_newtype(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    let span = tokens.expect(&Token::Ident(String::from("type")))?;

    let name = parse_path(tokens)?;

    let mut generics = Vec::new();

    while !tokens.is(&Token::Eq) {
        let quote_span = tokens.expect(&Token::Quote)?;
        let (name, name_span) = parse_ident(tokens)?;
        generics.push((name, quote_span.join(name_span)));
    }

    tokens.expect(&Token::Eq)?;

    let (token, _) = tokens.peek();

    match token {
        Token::LBrace => {
            let fields = parse_fields(tokens)?;

            let kind = NewtypeKind::Record(fields);

            let newtype = Newtype {
                name,
                generics,
                kind,
                span,
            };

            Ok(Item::Newtype(newtype))
        }

        _ => {
            let mut variants = vec![parse_variant(tokens)?];

            while is_variant(tokens) {
                consume_newlines(tokens);

                tokens.expect(&Token::Pipe)?;

                let variant = parse_variant(tokens)?;
                variants.push(variant);
            }

            let kind = NewtypeKind::Union(variants);

            let newtype = Newtype {
                name,
                generics,
                kind,
                span,
            };

            Ok(Item::Newtype(newtype))
        }
    }
}

fn parse_alias(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    let span = tokens.expect(&Token::Ident(String::from("alias")))?;

    let name = parse_path(tokens)?;

    let mut generics = Vec::new();

    while !tokens.is(&Token::Eq) {
        let quote_span = tokens.expect(&Token::Quote)?;
        let (name, name_span) = parse_ident(tokens)?;
        generics.push((name, quote_span.join(name_span)));
    }

    tokens.expect(&Token::Eq)?;

    let aliased = parse_type(tokens)?;

    let kind = NewtypeKind::Alias(aliased);

    let newtype = Newtype {
        name,
        generics,
        kind,
        span,
    };

    Ok(Item::Newtype(newtype))
}

fn parse_function(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    let span = tokens.expect("fn")?;

    let name = parse_path(tokens)?;

    if tokens.is(&Token::Colon) {
        tokens.consume();

        let ty = parse_type(tokens)?;

        let ascription = Ascription { name, ty, span };
        return Ok(Item::Ascription(ascription));
    }

    let mut params = Vec::new();

    while !(tokens.is(&Token::LBrace) || tokens.is(&Token::RArrow)) {
        let param = parse_irrefutable_pattern(tokens)?;
        params.push(param);
    }

    let (token, _) = tokens.peek();

    let body = match token {
        Token::LBrace => Some(parse_block_expr(tokens)?),

        Token::RArrow => {
            tokens.consume();
            Some(parse_expr(tokens)?)
        }

        _ => unreachable!(),
    };

    let function = Function {
        name,
        params,
        body,
        span,
    };

    Ok(Item::Function(function))
}

fn parse_extern(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    let span = tokens.expect("extern")?;

    let name = parse_path(tokens)?;

    tokens.expect(&Token::Colon)?;

    let ty = parse_type(tokens)?;

    let r#extern = Extern { name, ty, span };

    Ok(Item::Extern(r#extern))
}

fn parse_item(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    let (token, span) = tokens.peek();

    match token {
        Token::Ident(ident) => match ident.as_str() {
            "type" => parse_newtype(tokens),
            "alias" => parse_alias(tokens),
            "fn" => parse_function(tokens),
            "import" => parse_import(tokens),
            "extern" => parse_extern(tokens),
            _ => {
                let diagnostic = Diagnostic::error("expected item").with_span(span);
                Err(diagnostic)
            }
        },

        _ => {
            let diagnostic = Diagnostic::error("expected item").with_span(span);
            Err(diagnostic)
        }
    }
}

pub fn parse_file(tokens: &mut TokenStream, emitter: &mut dyn Emitter) -> Result<File, File> {
    let mut items = Vec::new();
    let mut is_error = false;

    consume_newlines(tokens);

    while !tokens.is(&Token::Eof) {
        match parse_item(tokens) {
            Ok(item) => items.push(item),
            Err(err) => {
                emitter.emit(err);
                is_error = true;
                break;
            }
        }

        consume_newlines(tokens);
    }

    if is_error {
        return Err(File { items });
    }

    Ok(File { items })
}
