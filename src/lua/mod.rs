use std::io::{self, Write};

use crate::ir::typed as ir;

const PRELUDE: &str = include_str!("prelude.lua");

pub fn codegen(f: &mut dyn Write, ir: &ir::Program, entry: ir::Bid) -> io::Result<()> {
    writeln!(f, "{PRELUDE}")?;

    for (bid, body) in ir.bodies.iter() {
        write!(f, "M[\"body{}\"] = function()", bid.index())?;

        match body.expr.is_some() {
            true => writeln!(f, " -- body {}", body.name)?,
            false => writeln!(f, " -- extern {}", body.name)?,
        }

        for (i, _) in body.inputs.iter().enumerate() {
            writeln!(f, "  return function(p{i})")?;
        }

        for (i, local) in body.locals.values().enumerate() {
            writeln!(f, "    local l{} -- local '{}'", i, local.name)?;
        }

        let mut codegen = Codegen {
            body: String::new(),
            indent: 4,
            temp: 0,
        };

        for (i, pattern) in body.inputs.iter().enumerate() {
            let param = format!("p{i}");
            codegen.pattern_assign(pattern, &param);
        }

        match body.expr {
            Some(ref expr) => {
                let expr = codegen.expr(expr);
                write!(f, "{}", &codegen.body)?;
                writeln!(f, "    return {expr}")?;
            }

            None => {
                writeln!(f, "    return E[\"{}\"]()", body.name)?;
            }
        }

        for _ in &body.inputs {
            writeln!(f, "  end")?;
        }

        writeln!(f, "end\n")?;
    }

    writeln!(f, "M[\"body{}\"]()", entry.index(),)?;

    Ok(())
}

struct Codegen {
    body: String,
    indent: usize,
    temp: usize,
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
            ir::ExprKind::Int(value) => format!("{value}"),
            ir::ExprKind::Bool(value) => format!("{value}"),
            ir::ExprKind::String(value) => format!("\"{value}\""),
            ir::ExprKind::Local(lid) => format!("l{}", lid.index()),

            ir::ExprKind::Format(parts) => parts
                .iter()
                .map(|part| format!("toString({}, true)", self.expr(part)))
                .collect::<Vec<_>>()
                .join(".."),

            ir::ExprKind::Body(bid) => format!("M[\"body{}\"]()", bid.index()),

            ir::ExprKind::Let(pattern, expr) => {
                let value = self.expr(expr);
                self.pattern_assign(pattern, &value);
                String::from("nil")
            }

            ir::ExprKind::Variant(name, None) => format!("{{ tag = \"{name}\" }}"),

            ir::ExprKind::Variant(name, Some(expr)) => {
                let value = self.expr(expr);
                format!("{{ tag = \"{name}\", value = {value} }}")
            }

            ir::ExprKind::ListEmpty => String::from("{ __list = true }"),

            ir::ExprKind::ListCons(head, tail) => {
                let head_value = self.expr(head);
                let tail_value = self.expr(tail);
                format!("{{ __list = true, {head_value}, {tail_value} }}")
            }

            ir::ExprKind::Tuple(items) => {
                let items = items.iter().map(|i| self.expr(i)).collect::<Vec<_>>();
                format!("{{ __tuple = true, {} }}", items.join(", "))
            }

            ir::ExprKind::Record(fields) => {
                let fields = fields
                    .iter()
                    .map(|(name, expr)| format!("[\"{}\"] = {}", name, self.expr(expr)))
                    .collect::<Vec<_>>();

                format!("{{ {} }}", fields.join(", "))
            }

            ir::ExprKind::With(target, fields) => {
                let temp = self.temp;
                self.temp += 1;

                let target = self.expr(target);
                self.line(format!("local t{temp} = copy({target}) -- with target"));

                for (name, expr) in fields {
                    let value = self.expr(expr);
                    self.line(format!("t{temp}[\"{name}\"] = {value} -- with field"));
                }

                format!("t{temp}")
            }

            ir::ExprKind::Try(value) => {
                let value = self.expr(value);
                self.line(format!("result = {value} -- try"));
                self.line("if result.tag == \"err\" then");
                self.line("  return result -- try err return");
                self.line("end");

                String::from("result.value")
            }

            ir::ExprKind::Call(callee, input) => {
                let callee = self.expr(callee);
                let input = self.expr(input);
                format!("({callee})({input})")
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
                    ir::BinOp::Shl => "<<",
                    ir::BinOp::Shr => ">>",
                    ir::BinOp::And => "and",
                    ir::BinOp::Or => "or",
                    ir::BinOp::Eq => return format!("equal({lhs}, {rhs})"),
                    ir::BinOp::Ne => return format!("(not equal({lhs}, {rhs}))"),
                    ir::BinOp::Lt => "<",
                    ir::BinOp::Le => "<=",
                    ir::BinOp::Gt => ">",
                    ir::BinOp::Ge => ">=",
                };

                format!("({lhs} {up} {rhs})")
            }

            ir::ExprKind::Match(target, arms) => {
                let temp = self.temp;
                self.temp += 1;

                let target = self.expr(target);

                self.line(format!("local v = {target} -- match target"));
                self.line(format!("local match_result{temp} -- match result"));

                for (i, arm) in arms.iter().enumerate() {
                    let check = codegen_pattern_check(&arm.pattern, "v");

                    let r#if = if i == 0 { "if" } else { "elseif" };
                    self.line(format!("{if} {check} then -- match arm"));

                    self.indent();
                    self.pattern_assign(&arm.pattern, "v");

                    let expr = self.expr(&arm.expr);
                    self.line(format!("match_result{temp} = {expr}"));
                    self.dedent();
                }

                self.line("end");

                format!("match_result{temp}")
            }

            ir::ExprKind::Field(target, name) => {
                let target = self.expr(target);
                format!("{target}[\"{name}\"]")
            }

            ir::ExprKind::Block(exprs) => {
                let temp = self.temp;
                self.temp += 1;

                self.line(format!("local block_result{temp} -- block result"));
                self.line("do -- block");
                self.indent();

                for expr in exprs {
                    let value = self.expr(expr);
                    self.line(format!("block_result{temp} = {value}"));
                }

                self.dedent();
                self.line("end");
                format!("block_result{temp}")
            }
        }
    }

    fn pattern_assign(&mut self, pattern: &ir::Pattern, value: &str) {
        match &pattern.kind {
            ir::PatternKind::Wildcard
            | ir::PatternKind::Int(_)
            | ir::PatternKind::Bool(_)
            | ir::PatternKind::String(_)
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
                let temp = self.temp;
                self.temp += 1;
                self.line(format!("local t{temp} = {value} -- tuple pattern assign"));

                for (i, item) in items.iter().enumerate() {
                    let item_value = format!("t{temp}[{}]", i + 1);
                    self.pattern_assign(item, &item_value);
                }
            }

            ir::PatternKind::Variant(_, _, Some(pattern)) => {
                let value = format!("{value}.value");
                self.pattern_assign(pattern, &value);
            }

            ir::PatternKind::ListCons(head, tail) => {
                self.pattern_assign(head, &format!("({value})[1]"));
                self.pattern_assign(tail, &format!("({value})[2]"));
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

        ir::PatternKind::Int(integer) => format!("({integer} == {value})"),
        ir::PatternKind::Bool(boolean) => format!("({boolean} == {value})"),
        ir::PatternKind::String(string) => format!("(\"{string}\" == {value})"),

        ir::PatternKind::Variant(_, variant, pattern) => match pattern {
            Some(p) => {
                let check = codegen_pattern_check(p, &format!("{value}.value"));
                format!("{value}.tag == \"{variant}\" and {check}")
            }
            None => format!("{value}.tag == \"{variant}\""),
        },

        ir::PatternKind::ListEmpty => format!("#{value} == 0"),

        ir::PatternKind::ListCons(head, tail) => {
            let head_check = codegen_pattern_check(head, &format!("({value})[1]"));
            let tail_check = codegen_pattern_check(tail, &format!("({value})[2]"));

            format!("#{value} > 0 and {head_check} and {tail_check}")
        }
    }
}
