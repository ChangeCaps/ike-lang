use crate::{
    ast::{Arm, BinOp, Expr, ExprKind},
    diagnostic::Diagnostic,
};

use super::{
    Token, TokenStream, consume_newlines, parse_ident, parse_irrefutable_pattern, parse_path,
    parse_pattern, tokenize,
};

#[derive(Clone, Copy)]
struct Options {
    allow_block: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self { allow_block: true }
    }
}

impl Options {
    fn allow_block(mut self, allow: bool) -> Self {
        self.allow_block = allow;
        self
    }
}

fn parse_bool_expr(tokens: &mut TokenStream) -> Result<Expr, Diagnostic> {
    let value = tokens.is(&Token::True);
    let span = tokens.consume();
    Ok(ExprKind::Bool(value).with_span(span))
}

fn parse_paren_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    tokens.expect(&Token::LParen)?;
    let expr = parse_expr_impl(tokens, options.allow_block(true))?;
    tokens.expect(&Token::RParen)?;

    Ok(expr)
}

fn parse_list_expr(tokens: &mut TokenStream) -> Result<Expr, Diagnostic> {
    let start = tokens.expect(&Token::LBracket)?;

    let mut elements = Vec::new();
    let mut rest = None;

    consume_newlines(tokens);

    while !tokens.is(&Token::RBracket) {
        if tokens.is(&Token::DotDot) {
            tokens.consume();
            let rest_expr = parse_expr_impl(tokens, Options::default())?;
            rest = Some(Box::new(rest_expr));
            break;
        }

        let element = parse_expr_impl(tokens, Options::default())?;
        elements.push(element);

        if !(tokens.is(&Token::RBracket) || tokens.is(&Token::Newline)) {
            tokens.expect(&Token::Semi)?;
        }

        consume_newlines(tokens);
    }

    let end = tokens.expect(&Token::RBracket)?;

    let span = start.join(end);
    let kind = ExprKind::List(elements, rest);
    Ok(kind.with_span(span))
}

pub fn parse_block_expr(tokens: &mut TokenStream) -> Result<Expr, Diagnostic> {
    let mut exprs = Vec::new();

    let start = tokens.expect(&Token::LBrace)?;

    consume_newlines(tokens);

    while !tokens.is(&Token::RBrace) {
        let expr = parse_expr_impl(tokens, Options::default())?;
        exprs.push(expr);

        if !tokens.is(&Token::RBrace) {
            tokens.expect(&Token::Newline)?;
        }

        consume_newlines(tokens);
    }

    let end = tokens.expect(&Token::RBrace)?;

    let span = start.join(end);
    let kind = ExprKind::Block(exprs);
    Ok(kind.with_span(span))
}

fn parse_lambda_expr(tokens: &mut TokenStream) -> Result<Expr, Diagnostic> {
    let start = tokens.expect(&Token::Pipe)?;

    let mut params = Vec::new();

    while !tokens.is(&Token::Pipe) {
        let parma = parse_irrefutable_pattern(tokens)?;
        params.push(parma);
    }

    tokens.expect(&Token::Pipe)?;

    let body = parse_tuple_expr(tokens, Options::default())?;

    let span = start.join(body.span);
    let kind = ExprKind::Lambda(params, Box::new(body));
    Ok(kind.with_span(span))
}

fn is_term_expr(token: &TokenStream, options: Options) -> bool {
    let (token, _) = token.peek();

    match token {
        Token::Ident(_)
        | Token::String(_)
        | Token::Integer(_)
        | Token::True
        | Token::False
        | Token::LParen
        | Token::LBracket
        | Token::Pipe => true,

        Token::LBrace if options.allow_block => true,

        _ => false,
    }
}

fn is_record_expr(tokens: &TokenStream) -> bool {
    if !tokens.is(&Token::LBrace) {
        return false;
    }

    let mut n = 1;
    while tokens.nth_is(n, &Token::Newline) {
        n += 1;
    }

    tokens.nth_is(n + 1, &Token::Colon)
}

fn parse_term_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let (token, span) = tokens.peek();

    match token {
        Token::Ident(_) => {
            let path = parse_path(tokens)?;
            let span = path.span;

            if is_record_expr(tokens) {
                tokens.expect(&Token::LBrace)?;

                consume_newlines(tokens);

                let mut fields = Vec::new();

                while !tokens.is(&Token::RBrace) {
                    let (name, span) = parse_ident(tokens)?;

                    tokens.expect(&Token::Colon)?;

                    let value = parse_expr_impl(tokens, Options::default())?;

                    fields.push((name, value, span));

                    if !(tokens.is(&Token::Newline) || tokens.is(&Token::RBrace)) {
                        tokens.expect(&Token::Semi)?;
                    }

                    consume_newlines(tokens);
                }

                let end = tokens.expect(&Token::RBrace)?;

                let span = path.span.join(end);
                let kind = ExprKind::Record(path, fields);
                return Ok(kind.with_span(span));
            }

            Ok(ExprKind::Path(path).with_span(span))
        }

        Token::String(value) => {
            tokens.consume();

            let mut rest = value.as_str();
            let mut parts = Vec::new();

            while let Some(idx) = rest.find("{") {
                if rest[idx..].starts_with("{{") {
                    rest = &rest[idx + 2..];
                    continue;
                }

                let Some(end) = rest[idx..].find("}") else {
                    let diagnostic = Diagnostic::error("no end of expression in format string")
                        .with_label(span, "in string here");

                    return Err(diagnostic);
                };

                let lit = rest[..idx].replace("{{", "{").replace("}}", "}");
                let lit = ExprKind::String(lit).with_span(span);
                parts.push(lit);

                let mut emitter = Vec::new();
                let mut tokens = tokenize(&rest[idx + 1..idx + end], span.id, &mut emitter)
                    .map_err(|_| emitter.pop().unwrap())?;

                let expr = parse_expr(&mut tokens)?;
                parts.push(expr);

                rest = &rest[idx + end + 1..];
            }

            if parts.is_empty() {
                let lit = value.replace("{{", "{").replace("}}", "}");
                return Ok(ExprKind::String(lit).with_span(span));
            }

            let lit = rest.replace("{{", "{").replace("}}", "}");
            let lit = ExprKind::String(lit).with_span(span);
            parts.push(lit);

            Ok(ExprKind::Format(parts).with_span(span))
        }

        Token::Integer(value) => {
            tokens.consume();
            Ok(ExprKind::Int(value).with_span(span))
        }

        Token::True | Token::False => parse_bool_expr(tokens),
        Token::LParen => parse_paren_expr(tokens, options),
        Token::LBrace => parse_block_expr(tokens),
        Token::LBracket => parse_list_expr(tokens),
        Token::Pipe => parse_lambda_expr(tokens),

        _ => {
            let diagnostic = Diagnostic::error("unexpected token in expression").with_span(span);
            Err(diagnostic)
        }
    }
}

fn parse_field_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let mut expr = parse_term_expr(tokens, options)?;

    while tokens.is(&Token::Dot) {
        tokens.consume();

        let (name, name_span) = parse_ident(tokens)?;

        let span = name_span.join(expr.span);
        let kind = ExprKind::Field(Box::new(expr), name, name_span);
        expr = kind.with_span(span);
    }

    Ok(expr)
}

fn parse_call_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let mut callee = parse_field_expr(tokens, options)?;

    while is_term_expr(tokens, options) {
        let input = parse_field_expr(tokens, options)?;

        let span = callee.span.join(input.span);
        let kind = ExprKind::Call(Box::new(callee), Box::new(input));
        callee = kind.with_span(span);
    }

    Ok(callee)
}

fn parse_try_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    if tokens.is(&Token::Try) {
        let span = tokens.consume();
        let expr = parse_try_expr(tokens, options)?;

        let kind = ExprKind::Try(Box::new(expr));
        return Ok(Expr { kind, span });
    }

    parse_call_expr(tokens, options)
}

fn parse_mul_div_mod_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let mut lhs = parse_try_expr(tokens, options)?;

    let (mut token, op_span) = tokens.peek();

    while matches!(token, Token::Star | Token::Slash | Token::Percent) {
        tokens.consume();

        let rhs = parse_try_expr(tokens, options)?;

        let op = match token {
            Token::Star => BinOp::Mul,
            Token::Slash => BinOp::Div,
            Token::Percent => BinOp::Mod,
            _ => unreachable!(),
        };

        let span = lhs.span.join(rhs.span);
        let kind = ExprKind::Binary(op, op_span, Box::new(lhs), Box::new(rhs));
        lhs = kind.with_span(span);

        (token, _) = tokens.peek();
    }

    Ok(lhs)
}

fn parse_add_sub_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let mut lhs = parse_mul_div_mod_expr(tokens, options)?;

    let (mut token, op_span) = tokens.peek();

    while matches!(token, Token::Plus | Token::Minus) {
        tokens.consume();

        let rhs = parse_mul_div_mod_expr(tokens, options)?;

        let op = match token {
            Token::Plus => BinOp::Add,
            Token::Minus => BinOp::Sub,
            _ => unreachable!(),
        };

        let span = lhs.span.join(rhs.span);
        let kind = ExprKind::Binary(op, op_span, Box::new(lhs), Box::new(rhs));
        lhs = kind.with_span(span);

        (token, _) = tokens.peek();
    }

    Ok(lhs)
}

fn parse_cmp_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let mut lhs = parse_add_sub_expr(tokens, options)?;

    let (mut token, op_span) = tokens.peek();

    while matches!(token, Token::Gt | Token::Lt | Token::GtEq | Token::LtEq) {
        tokens.consume();

        let rhs = parse_add_sub_expr(tokens, options)?;

        let op = match token {
            Token::Gt => BinOp::Gt,
            Token::Lt => BinOp::Lt,
            Token::GtEq => BinOp::Ge,
            Token::LtEq => BinOp::Le,
            _ => unreachable!(),
        };

        let span = lhs.span.join(rhs.span);
        let kind = ExprKind::Binary(op, op_span, Box::new(lhs), Box::new(rhs));
        lhs = kind.with_span(span);

        (token, _) = tokens.peek();
    }

    Ok(lhs)
}

fn parse_eq_ne_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let mut lhs = parse_cmp_expr(tokens, options)?;

    let (mut token, op_span) = tokens.peek();

    while matches!(token, Token::EqEq | Token::NotEq) {
        tokens.consume();

        let rhs = parse_cmp_expr(tokens, options)?;

        let op = match token {
            Token::EqEq => BinOp::Eq,
            Token::NotEq => BinOp::Ne,
            _ => unreachable!(),
        };

        let span = lhs.span.join(rhs.span);
        let kind = ExprKind::Binary(op, op_span, Box::new(lhs), Box::new(rhs));
        lhs = kind.with_span(span);

        (token, _) = tokens.peek();
    }

    Ok(lhs)
}

fn parse_and_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let lhs = parse_eq_ne_expr(tokens, options)?;

    if !tokens.is(&Token::And) {
        return Ok(lhs);
    }

    let op_span = tokens.consume();

    let rhs = parse_and_expr(tokens, options)?;

    let span = lhs.span.join(rhs.span);
    let kind = ExprKind::Binary(BinOp::And, op_span, Box::new(lhs), Box::new(rhs));
    Ok(kind.with_span(span))
}

fn parse_or_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let lhs = parse_and_expr(tokens, options)?;

    if !tokens.is(&Token::Or) {
        return Ok(lhs);
    }

    let op_span = tokens.consume();

    let rhs = parse_or_expr(tokens, options)?;

    let span = lhs.span.join(rhs.span);
    let kind = ExprKind::Binary(BinOp::Or, op_span, Box::new(lhs), Box::new(rhs));
    Ok(kind.with_span(span))
}

fn parse_tuple_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let expr = parse_or_expr(tokens, options)?;

    if !tokens.is(&Token::Comma) {
        return Ok(expr);
    }

    let mut span = expr.span;
    let mut items = vec![expr];

    while tokens.is(&Token::Comma) {
        tokens.consume();

        let next_expr = parse_or_expr(tokens, options)?;
        span = span.join(next_expr.span);
        items.push(next_expr);
    }

    Ok(ExprKind::Tuple(items).with_span(span))
}

fn is_pipe_left_expr(tokens: &TokenStream) -> bool {
    let mut n = 0;

    while tokens.nth_is(n, &Token::Newline) {
        n += 1;
    }

    tokens.nth_is(n, &Token::LtPipe)
}

fn is_pipe_right_expr(tokens: &TokenStream) -> bool {
    let mut n = 0;

    while tokens.nth_is(n, &Token::Newline) {
        n += 1;
    }

    tokens.nth_is(n, &Token::PipeGt)
}

fn parse_pipe_left_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let mut expr = parse_tuple_expr(tokens, options)?;

    while is_pipe_left_expr(tokens) {
        consume_newlines(tokens);
        tokens.expect(&Token::LtPipe)?;

        let input = parse_tuple_expr(tokens, options)?;

        let span = expr.span.join(input.span);
        let kind = ExprKind::Call(Box::new(expr), Box::new(input));
        expr = kind.with_span(span);
    }

    Ok(expr)
}

fn parse_pipe_right_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let mut expr = parse_pipe_left_expr(tokens, options)?;

    while is_pipe_right_expr(tokens) {
        consume_newlines(tokens);
        tokens.expect(&Token::PipeGt)?;

        let callee = parse_pipe_left_expr(tokens, options)?;

        let span = expr.span.join(callee.span);
        let kind = ExprKind::Call(Box::new(callee), Box::new(expr));
        expr = kind.with_span(span);
    }

    Ok(expr)
}

fn parse_let_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let span = tokens.expect(&Token::Let)?;

    let pattern = parse_pattern(tokens)?;

    tokens.expect(&Token::Eq)?;

    let value = parse_expr_impl(tokens, options)?;

    let span = span.join(value.span);
    let kind = ExprKind::Let(pattern, Box::new(value));
    Ok(kind.with_span(span))
}

fn parse_match_expr(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    tokens.expect(&Token::Match)?;

    let expr = parse_expr_impl(tokens, options.allow_block(false))?;

    tokens.expect(&Token::LBrace)?;

    let mut arms = Vec::new();

    consume_newlines(tokens);

    while !tokens.is(&Token::RBrace) {
        let pattern = parse_pattern(tokens)?;

        tokens.expect(&Token::RArrow)?;

        let expr = parse_expr_impl(tokens, options)?;

        let span = pattern.span.join(expr.span);
        let arm = Arm {
            pattern,
            expr,
            span,
        };
        arms.push(arm);

        consume_newlines(tokens);
    }

    let end = tokens.expect(&Token::RBrace)?;

    let span = expr.span.join(end);
    let kind = ExprKind::Match(Box::new(expr), arms);
    Ok(kind.with_span(span))
}

fn parse_expr_impl(tokens: &mut TokenStream, options: Options) -> Result<Expr, Diagnostic> {
    let (token, _) = tokens.peek();

    match token {
        Token::Let => parse_let_expr(tokens, options),
        Token::Match => parse_match_expr(tokens, options),
        _ => parse_pipe_right_expr(tokens, options),
    }
}

pub fn parse_expr(tokens: &mut TokenStream) -> Result<Expr, Diagnostic> {
    parse_expr_impl(tokens, Options::default())
}
