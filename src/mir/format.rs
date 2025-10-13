use std::io::{self, Write};

use crate::mir::{Body, Operand, Place, Projection, Statement, Terminator, Type, Unit, Value};

use super::{Constant, PlaceKind};

pub struct Formatter<W> {
    writer: W,
}

impl<W: Write> Formatter<W> {
    pub fn new(writer: W) -> Self {
        Self { writer }
    }

    pub fn format_unit(&mut self, unit: &Unit) -> io::Result<()> {
        for body in unit.bodies() {
            self.format_body(body)?;
        }

        Ok(())
    }

    fn format_body(&mut self, body: &Body) -> io::Result<()> {
        write!(
            self.writer,
            "fn {name}(",
            name = body.name.as_deref().unwrap_or("{fn}"),
        )?;

        for (i, argument) in body.arguments.iter().enumerate() {
            self.format_type(argument)?;

            if i < body.arguments.len() - 1 {
                write!(self.writer, ", ")?;
            }
        }

        write!(self.writer, ") -> ")?;

        self.format_type(&body.output)?;

        write!(self.writer, " {{")?;

        for (i, local) in body.locals.iter().enumerate() {
            write!(self.writer, "\n  ")?;
            write!(self.writer, "l{i}: ")?;
            self.format_type(local)?;
        }

        if !body.locals.is_empty() {
            writeln!(self.writer)?;
        }

        for (i, block) in body.blocks.iter().enumerate() {
            write!(self.writer, "\n  bb{i}: {{")?;

            for statement in block.statements.iter() {
                write!(self.writer, "\n    ")?;
                self.format_statement(statement)?;
            }

            write!(self.writer, "\n    ")?;
            self.format_terminator(&block.terminator)?;

            write!(self.writer, "\n  }}")?;
        }

        write!(self.writer, "\n}}")?;

        Ok(())
    }

    fn format_terminator(&mut self, terminator: &Terminator) -> io::Result<()> {
        match terminator {
            Terminator::Return(value) => {
                write!(self.writer, "return ")?;
                self.format_value(value)?;

                Ok(())
            }

            Terminator::Jump(block_id) => {
                write!(self.writer, "jump {}", block_id.index)
            }
        }
    }

    fn format_statement(&mut self, statement: &Statement) -> io::Result<()> {
        match statement {
            Statement::Assign(place, value) => {
                self.format_place(place)?;
                write!(self.writer, " = ")?;
                self.format_value(value)?;

                Ok(())
            }
        }
    }

    fn format_place(&mut self, place: &Place) -> io::Result<()> {
        match place.kind {
            PlaceKind::Argument(index) => write!(self.writer, "a{index}")?,
            PlaceKind::Local(index) => write!(self.writer, "l{index}")?,
        }

        for projection in place.proj.iter() {
            match projection {
                Projection::Field(index) => write!(self.writer, ".{index}")?,
            }
        }

        Ok(())
    }

    fn format_operand(&mut self, operand: &Operand) -> io::Result<()> {
        match operand {
            Operand::Copy(place) => self.format_place(place),
            Operand::Constant(constant) => match constant {
                Constant::None => write!(self.writer, "none"),
                Constant::Num(value) => write!(self.writer, "{value}"),
                Constant::Bool(value) => write!(self.writer, "{value}"),
            },
        }
    }

    fn format_value(&mut self, value: &Value) -> io::Result<()> {
        match value {
            Value::Use(operand) => self.format_operand(operand),

            Value::Binary(op, lhs, rhs) => {
                self.format_operand(lhs)?;
                write!(self.writer, " {op:?} ")?;
                self.format_operand(rhs)?;

                Ok(())
            }

            Value::Record(fields) => {
                write!(self.writer, "{{ ")?;

                for (i, field) in fields.iter().enumerate() {
                    self.format_operand(field)?;

                    if i < fields.len() - 1 {
                        write!(self.writer, ", ")?;
                    }
                }

                write!(self.writer, " }}")
            }
        }
    }

    fn format_type(&mut self, ty: &Type) -> io::Result<()> {
        match ty {
            Type::Num => write!(self.writer, "num"),
            Type::Str => write!(self.writer, "str"),
            Type::Bool => write!(self.writer, "bool"),
            Type::Never => write!(self.writer, "!"),

            Type::List(elem) => {
                write!(self.writer, "[")?;
                self.format_type(elem)?;
                write!(self.writer, "]")
            }

            Type::Fn(inputs, output) => {
                write!(self.writer, "fn(")?;

                for (i, input) in inputs.iter().enumerate() {
                    self.format_type(input)?;

                    if i < inputs.len() - 1 {
                        write!(self.writer, ", ")?;
                    }
                }

                write!(self.writer, ") -> ")?;
                self.format_type(output)
            }

            Type::Record(fields) => {
                write!(self.writer, "{{ ")?;

                for (i, field) in fields.iter().enumerate() {
                    self.format_type(field)?;

                    if i < fields.len() - 1 {
                        write!(self.writer, ", ")?;
                    }
                }

                write!(self.writer, " }}")
            }

            Type::Union(variants) => {
                for (i, variant) in variants.iter().enumerate() {
                    self.format_type(variant)?;

                    if i < variants.len() - 1 {
                        write!(self.writer, " | ")?;
                    }
                }

                Ok(())
            }
        }
    }
}
