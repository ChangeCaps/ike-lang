use crate::ir::typed as ir;

const PRELUDE: &str = include_str!("prelude.lua");

pub fn codegen(ir: &ir::Program, entry: ir::Bid) -> String {
    let mut code = PRELUDE.to_string();
    code += "\n";

    for (bid, body) in ir.bodies.iter() {
        code += &format!("M[\"body{}\"] = function()", bid.index());

        match body.expr.is_some() {
            true => code += &format!(" -- body {}", body.name),
            false => code += &format!(" -- extern {}", body.name),
        }

        code += "\n";

        for (i, _) in body.inputs.iter().enumerate() {
            code += &format!("  return function(p{})\n", i);
        }

        for (i, _) in body.locals.values().enumerate() {
            if i < body.inputs.len() {
                code += &format!("    local l{} = p{}\n", i, i);
            } else {
                code += &format!("    local l{}\n", i);
            }
        }

        for (i, pattern) in body.inputs.iter().enumerate() {
            let param = format!("p{}", i);

            code += "    ";
            code += &codegen_pattern_assign(pattern, &param);
            code += "\n";
        }

        match body.expr {
            Some(ref expr) => {
                let expr = codegen_expr(expr);
                code += &indent(indent(format!("return {}", expr)));
                code += "\n";
            }

            None => {
                code += &format!("    return E[\"{}\"]\n", body.name);
            }
        }

        for _ in &body.inputs {
            code += "  end\n";
        }

        code += "end\n\n";
    }

    code += &format!("M[\"body{}\"]()", entry.index());
    code
}

fn codegen_expr(expr: &ir::Expr) -> String {
    match &expr.kind {
        ir::ExprKind::Int(value) => format!("{}", value),
        ir::ExprKind::Bool(value) => format!("{}", value),
        ir::ExprKind::String(value) => format!("\"{}\"", value),
        ir::ExprKind::Local(lid) => format!("l{}", lid.index()),

        ir::ExprKind::Body(bid) => {
            format!("M[\"body{}\"]()", bid.index())
        }

        ir::ExprKind::Let(pattern, expr) => {
            let value = codegen_expr(expr);
            codegen_pattern_assign(pattern, &value)
        }

        ir::ExprKind::Call(target, value) => {
            let target_code = codegen_expr(target);
            let value_code = codegen_expr(value);
            format!("({})({})", target_code, value_code)
        }

        ir::ExprKind::ListEmpty => String::from("{}"),

        ir::ExprKind::ListCons(head, tail) => {
            let head = codegen_expr(head);
            let tail = codegen_expr(tail);

            format!("{{ __list = true, {}, {} }}", head, tail)
        }

        ir::ExprKind::Tuple(exprs) => {
            let mut code = String::from("({ __tuple = true, ");

            for (i, e) in exprs.iter().enumerate() {
                if i > 0 {
                    code += ", ";
                }

                code += &codegen_expr(e);
            }

            code + "})"
        }

        ir::ExprKind::Variant(name, value) => match value {
            Some(value) => {
                let value_code = codegen_expr(value);
                format!("{{ tag = \"{}\", value = {} }}", name, value_code)
            }
            None => format!("{{ tag = \"{}\" }}", name),
        },

        ir::ExprKind::Record(fields) => {
            let mut code = String::from("{");

            for (i, (name, value)) in fields.iter().enumerate() {
                if i > 0 {
                    code += ", ";
                }

                let value_code = codegen_expr(value);
                code += &format!("{} = {}", name, value_code);
            }

            code + "}"
        }

        ir::ExprKind::Binary(op, left, right) => {
            let left_code = codegen_expr(left);
            let right_code = codegen_expr(right);

            let op_str = match op {
                ir::BinOp::Add => "+",
                ir::BinOp::Sub => "-",
                ir::BinOp::Mul => "*",
                ir::BinOp::Div => "/",
                ir::BinOp::Mod => "%",
                ir::BinOp::And => "and",
                ir::BinOp::Or => "or",
                ir::BinOp::Gt => ">",
                ir::BinOp::Lt => "<",
                ir::BinOp::Ge => ">=",
                ir::BinOp::Le => "<=",
                ir::BinOp::Eq => "==",
                ir::BinOp::Ne => "~=",
            };

            format!("({} {} {})", left_code, op_str, right_code)
        }

        ir::ExprKind::Field(target, name) => {
            let target_code = codegen_expr(target);
            format!("{}.{}", target_code, name)
        }

        ir::ExprKind::Match(target, arms) => {
            let target = codegen_expr(target);

            let mut code = format!("(function() -- match\n  local v = {}\n", target);

            for (i, arm) in arms.iter().enumerate() {
                let check = codegen_pattern_check(&arm.pattern, "v");
                let assign = codegen_pattern_assign(&arm.pattern, "v");
                let expr = codegen_expr(&arm.expr);

                let r#if = if i == 0 { "if" } else { "elseif" };
                code += &format!("  {} {} then\n", r#if, check);

                if !assign.is_empty() {
                    code += &indent(indent(assign));
                    code += "\n";
                }

                code += &indent(indent(format!("return {}", expr)));
                code += "\n";
            }

            code + "  end\nend)()"
        }

        ir::ExprKind::Block(exprs) => {
            let mut code = String::from("(function() -- block\n");

            for (i, e) in exprs.iter().enumerate() {
                if i == exprs.len() - 1 {
                    code += &indent(format!("return {}", codegen_expr(e)));
                    code += "\n";
                } else {
                    code += &indent(codegen_expr(e));
                    code += ";";
                    code += "\n";
                }
            }

            code + "end)()"
        }
    }
}

fn codegen_pattern_check(pattern: &ir::Pattern, value: &str) -> String {
    match &pattern.kind {
        ir::PatternKind::Wildcard => String::from("true"),
        ir::PatternKind::Binding(_) => String::from("true"),

        ir::PatternKind::Tuple(items) => {
            let mut checks = Vec::new();

            for (i, item) in items.iter().enumerate() {
                let item_value = format!("{}[{}]", value, i + 1);
                let check = codegen_pattern_check(item, &item_value);
                checks.push(check);
            }

            checks.join(" and ")
        }

        ir::PatternKind::Bool(boolean) => format!("{} == {}", boolean, value),

        ir::PatternKind::Variant(_, variant, pattern) => match pattern {
            Some(p) => {
                let check = codegen_pattern_check(p, &format!("{}.value", value));
                format!("{}.tag == \"{}\" and {}", value, variant, check)
            }
            None => format!("{}.tag == \"{}\"", value, variant),
        },

        ir::PatternKind::ListEmpty => format!("#{} == 0", value),

        ir::PatternKind::ListCons(head, tail) => {
            let head_check = codegen_pattern_check(head, value);
            let tail_check = codegen_pattern_check(tail, value);

            format!("#{} > 0 and {} and {}", value, head_check, tail_check)
        }
    }
}

fn codegen_pattern_assign(pattern: &ir::Pattern, value: &str) -> String {
    match &pattern.kind {
        ir::PatternKind::Wildcard => String::new(),

        ir::PatternKind::Binding(lid) => format!("l{} = {}", lid.index(), value),

        ir::PatternKind::Tuple(items) => {
            let mut assignments = Vec::new();

            for (i, item) in items.iter().enumerate() {
                let item_value = format!("{}[{}]", value, i + 1);
                let assign = codegen_pattern_assign(item, &item_value);
                if !assign.is_empty() {
                    assignments.push(assign);
                }
            }

            assignments.join(";\n")
        }

        ir::PatternKind::Bool(_) => String::new(),

        ir::PatternKind::Variant(_, _, pattern) => match pattern {
            Some(p) => {
                let value = format!("{}.value", value);
                codegen_pattern_assign(p, &value)
            }
            None => String::new(),
        },

        ir::PatternKind::ListEmpty => String::new(),

        ir::PatternKind::ListCons(head, tail) => {
            let head_assign = codegen_pattern_assign(head, &format!("{}[1]", value));
            let tail_assign = codegen_pattern_assign(tail, &format!("{}[2]", value));

            format!("{};\n{}", head_assign, tail_assign)
        }
    }
}

fn indent(code: String) -> String {
    code.lines()
        .map(|line| format!("  {}", line))
        .collect::<Vec<_>>()
        .join("\n")
}
