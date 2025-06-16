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

        for (i, local) in body.locals.values().enumerate() {
            code += &format!("    local l{} -- local '{}'\n", i, local.name);
        }

        let mut codegen = Codegen {
            body: String::new(),
            indent: 4,
        };

        for (i, pattern) in body.inputs.iter().enumerate() {
            let param = format!("p{}", i);
            codegen.pattern_assign(pattern, &param);
        }

        match body.expr {
            Some(ref expr) => {
                let expr = codegen.expr(expr);
                code += &codegen.body;
                code += &format!("    return {}", expr);
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

struct Codegen {
    body: String,
    indent: usize,
}

impl Codegen {
    fn line(&mut self, line: impl AsRef<str>) {
        self.body += &" ".repeat(self.indent);
        self.body += line.as_ref();
        self.body += "\n";
    }

    fn indent(&mut self) {
        self.indent += 2;
    }

    fn dedent(&mut self) {
        if self.indent >= 2 {
            self.indent -= 2;
        }
    }

    fn expr(&mut self, expr: &ir::Expr) -> String {
        match &expr.kind {
            ir::ExprKind::Int(value) => format!("{}", value),
            ir::ExprKind::Bool(value) => format!("{}", value),
            ir::ExprKind::String(value) => format!("\"{}\"", value),
            ir::ExprKind::Local(lid) => format!("l{}", lid.index()),

            ir::ExprKind::Body(bid) => format!("M[\"body{}\"]()", bid.index()),

            ir::ExprKind::Let(pattern, expr) => {
                let value = self.expr(expr);
                self.pattern_assign(pattern, &value);
                String::from("nil")
            }

            ir::ExprKind::Variant(name, None) => format!("{{ tag = \"{}\" }}", name),

            ir::ExprKind::Variant(name, Some(expr)) => {
                let value = self.expr(expr);
                format!("{{ tag = \"{}\", value = {} }}", name, value)
            }

            ir::ExprKind::ListEmpty => String::from("{ __list = true }"),

            ir::ExprKind::ListCons(head, tail) => {
                let head_value = self.expr(head);
                let tail_value = self.expr(tail);
                format!("{{ __list = true, {}, {} }}", head_value, tail_value)
            }

            ir::ExprKind::Tuple(items) => {
                let items = items.iter().map(|i| self.expr(i)).collect::<Vec<_>>();
                format!("{{ __tuple = true, {} }}", items.join(", "))
            }

            ir::ExprKind::Record(fields) => {
                let fields = fields
                    .iter()
                    .map(|(name, expr)| format!("{} = {}", name, self.expr(expr)))
                    .collect::<Vec<_>>();

                format!("{{ {} }}", fields.join(", "))
            }

            ir::ExprKind::Call(callee, input) => {
                let callee = self.expr(callee);
                let input = self.expr(input);
                format!("({})({})", callee, input)
            }

            ir::ExprKind::Binary(op, lhs, rhs) => {
                let lhs = self.expr(lhs);
                let rhs = self.expr(rhs);

                let up = match op {
                    ir::BinOp::Add => "+",
                    ir::BinOp::Sub => "-",
                    ir::BinOp::Mul => "*",
                    ir::BinOp::Div => "/",
                    ir::BinOp::Mod => "%",
                    ir::BinOp::And => "and",
                    ir::BinOp::Or => "or",
                    ir::BinOp::Eq => "==",
                    ir::BinOp::Ne => "~=",
                    ir::BinOp::Lt => "<",
                    ir::BinOp::Le => "<=",
                    ir::BinOp::Gt => ">",
                    ir::BinOp::Ge => ">=",
                };

                format!("({} {} {})", lhs, up, rhs)
            }

            ir::ExprKind::Match(target, arms) => {
                let target = self.expr(target);

                self.line(format!("local v = {} -- match target", target));
                self.line("local match_result -- match result");

                for (i, arm) in arms.iter().enumerate() {
                    let check = codegen_pattern_check(&arm.pattern, "v");

                    let r#if = if i == 0 { "if" } else { "elseif" };
                    self.line(format!("{} {} then -- match", r#if, check));

                    self.indent();
                    self.pattern_assign(&arm.pattern, "v");

                    let expr = self.expr(&arm.expr);
                    self.line(format!("match_result = {}", expr));
                    self.dedent();
                }

                self.line("end");

                String::from("match_result")
            }

            ir::ExprKind::Field(target, name) => {
                let target = self.expr(target);
                format!("{}.{}", target, name)
            }

            ir::ExprKind::Block(exprs) => {
                self.line("local block_result -- block result");
                self.line("do -- block");
                self.indent();

                for expr in exprs {
                    let value = self.expr(expr);
                    self.line(format!("block_result = {}", value));
                }

                self.dedent();
                self.line("end");
                String::from("block_result")
            }
        }
    }

    fn pattern_assign(&mut self, pattern: &ir::Pattern, value: &str) {
        match &pattern.kind {
            ir::PatternKind::Wildcard
            | ir::PatternKind::Bool(_)
            | ir::PatternKind::ListEmpty
            | ir::PatternKind::Variant(_, _, None) => {}

            ir::PatternKind::Binding(lid) => {
                self.line(format!(
                    "l{} = {} -- pattern binding assign",
                    lid.index(),
                    value,
                ));
            }

            ir::PatternKind::Tuple(items) => {
                self.line(format!("local t = {} -- tuple pattern assign", value));

                for (i, item) in items.iter().enumerate() {
                    let item_value = format!("t[{}]", i + 1);
                    self.pattern_assign(item, &item_value);
                }
            }

            ir::PatternKind::Variant(_, _, Some(pattern)) => {
                let value = format!("{}.value", value);
                self.pattern_assign(pattern, &value);
            }

            ir::PatternKind::ListCons(head, tail) => {
                self.pattern_assign(head, &format!("({})[1]", value));
                self.pattern_assign(tail, &format!("({})[2]", value));
            }
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
            let head_check = codegen_pattern_check(head, &format!("({})[1]", value));
            let tail_check = codegen_pattern_check(tail, &format!("({})[2]", value));

            format!("#{} > 0 and {} and {}", value, head_check, tail_check)
        }
    }
}
