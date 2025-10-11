use std::{
    collections::HashMap,
    ops::{Deref, DerefMut, Index, IndexMut},
};

use crate::{ir, mir};

pub fn build(unit: &ir::Unit, entry: ir::BodyId) -> (mir::Unit, mir::BodyId) {
    let mut builder = Builder {
        ir_unit:  unit,
        mir_unit: mir::Unit::new(),
        types:    HashMap::new(),
        bodies:   HashMap::new(),
    };

    let entry = builder.build_body(entry, &[]);

    (builder.mir_unit, entry)
}

type TypeKey = (ir::NewtypeId, Vec<mir::Type>);
type BodyKey = (ir::BodyId, Vec<mir::Type>);

struct Builder<'a> {
    ir_unit:  &'a ir::Unit,
    mir_unit: mir::Unit,
    types:    HashMap<TypeKey, mir::TypeId>,
    bodies:   HashMap<BodyKey, mir::BodyId>,
}

impl Builder<'_> {
    fn build_body(&mut self, ir_body_id: ir::BodyId, generics: &[mir::Type]) -> mir::BodyId {
        let key = (ir_body_id, generics.to_vec());

        if let Some(&id) = self.bodies.get(&key) {
            return id;
        }

        let mir_body_id = self.mir_unit.reserve_body();
        self.bodies.insert(key, mir_body_id);

        let map = self.ir_unit[ir_body_id]
            .generics
            .iter()
            .map(|p| p.generic)
            .zip(generics.iter().cloned())
            .collect();

        let ir_body = &self.ir_unit[ir_body_id];
        let mut locals = Vec::new();

        for local in &ir_body.locals {
            let ty = self.build_type(&local.ty, &map);
            locals.push(ty);
        }

        let output = self.build_type(&ir_body.ty, &map);

        let mut body_builder = BodyBuilder {
            ir_body,
            builder: self,
            generics: &map,
            arguments: Vec::new(),
            locals,
            blocks: Vec::new(),
        };

        let mut block = body_builder.create_block();

        for (i, param) in body_builder.ir_body.params.iter().enumerate() {
            let ty = body_builder.build_type(&param.ty);
            body_builder.arguments.push(ty);

            let place = mir::Place::argument(i);
            body_builder.build_pattern(&mut block, &param.pattern, &place);
        }

        if let Some(ref expr) = body_builder.ir_body.expr {
            let value = body_builder.build_value(&mut block, expr);
            body_builder[block].r#return(value);
        }

        let mut blocks = Vec::new();

        for block in body_builder.blocks {
            blocks.push(mir::Block {
                statements: block.statements,
                terminator: block.terminator.unwrap(),
            });
        }

        let mir_body = mir::Body {
            arguments: body_builder.arguments,
            locals: body_builder.locals,
            blocks,
            output,
        };

        self.mir_unit.insert_body(mir_body_id, mir_body);

        mir_body_id
    }

    fn build_type(&mut self, ty: &ir::Type, map: &HashMap<ir::Generic, mir::Type>) -> mir::Type {
        match ty {
            ir::Type::Nat | ir::Type::Int | ir::Type::Num => mir::Type::Num,
            ir::Type::Str => mir::Type::Str,
            ir::Type::Bool => mir::Type::Bool,
            ir::Type::None => mir::Type::Record(Vec::new()),
            ir::Type::Never => mir::Type::Never,
            ir::Type::Body { .. } => mir::Type::Record(Vec::new()),

            ir::Type::Alias { alias_id, generics } => {
                let ty = self.ir_unit.instantiate_alias(*alias_id, generics);
                self.build_type(&ty, map)
            }

            ir::Type::Newtype {
                newtype_id,
                generics,
            } => {
                let ty = self.ir_unit.instantiate_newtype(*newtype_id, generics);
                self.build_type(&ty, map)
            }

            ir::Type::List(elem) => {
                let elem = self.build_type(elem, map);
                mir::Type::List(Box::new(elem))
            }

            ir::Type::Fn(inputs, output) => {
                let inputs = inputs.iter().map(|t| self.build_type(t, map)).collect();
                let output = self.build_type(output, map);
                mir::Type::Fn(inputs, Box::new(output))
            }

            ir::Type::Record(fields) => {
                let mut fields = fields.clone();
                fields.sort_by(|a, b| a.name.cmp(&b.name));

                let fields = fields.iter().map(|f| self.build_type(&f.ty, map)).collect();
                mir::Type::Record(fields)
            }

            ir::Type::Union(variants) => {
                let variants = variants.iter().map(|t| self.build_type(t, map)).collect();
                mir::Type::Union(variants)
            }

            ir::Type::Generic(generic) => map.get(generic).expect("").clone(),
            ir::Type::Unknown | ir::Type::Error => unreachable!(),
        }
    }
}

struct BodyBuilder<'a, 'b> {
    builder:   &'a mut Builder<'b>,
    ir_body:   &'a ir::Body,
    generics:  &'a HashMap<ir::Generic, mir::Type>,
    arguments: Vec<mir::Type>,
    locals:    Vec<mir::Type>,
    blocks:    Vec<BlockBuilder>,
}

#[derive(Debug, Default)]
struct BlockBuilder {
    statements: Vec<mir::Statement>,
    terminator: Option<mir::Terminator>,
}

impl<'b> Deref for BodyBuilder<'_, 'b> {
    type Target = Builder<'b>;

    fn deref(&self) -> &Self::Target {
        self.builder
    }
}

impl DerefMut for BodyBuilder<'_, '_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.builder
    }
}

impl Index<mir::BlockId> for BodyBuilder<'_, '_> {
    type Output = BlockBuilder;

    fn index(&self, id: mir::BlockId) -> &Self::Output {
        &self.blocks[id.index]
    }
}

impl IndexMut<mir::BlockId> for BodyBuilder<'_, '_> {
    fn index_mut(&mut self, id: mir::BlockId) -> &mut Self::Output {
        &mut self.blocks[id.index]
    }
}

impl BodyBuilder<'_, '_> {
    fn build_type(&mut self, ty: &ir::Type) -> mir::Type {
        self.builder.build_type(ty, self.generics)
    }

    fn create_block(&mut self) -> mir::BlockId {
        let index = self.blocks.len();
        self.blocks.push(BlockBuilder::default());
        mir::BlockId { index }
    }

    fn create_local(&mut self, ty: &ir::Type) -> usize {
        let ty = self.build_type(ty);
        let index = self.locals.len();
        self.locals.push(ty);
        index
    }

    fn build_pattern(
        &mut self,
        block: &mut mir::BlockId,
        pattern: &ir::Pattern,
        place: &mir::Place,
    ) {
        match pattern.kind {
            ir::PatternKind::Wildcard => {}
            ir::PatternKind::Binding(index) => {
                self[*block].assign(mir::Place::local(index), place.clone());
            }
        }
    }

    fn build_place(&mut self, block: &mut mir::BlockId, expr: &ir::Expr) -> mir::Place {
        match expr.kind {
            ir::ExprKind::Local(index) => mir::Place::local(index),

            ir::ExprKind::Promote(_, ref expr) => self.build_place(block, expr),
            ir::ExprKind::Demote(_, ref expr) => self.build_place(block, expr),

            ir::ExprKind::Block(ref exprs) if !exprs.is_empty() => {
                for (i, expr) in exprs.iter().enumerate() {
                    let place = self.build_place(block, expr);

                    if i == exprs.len() - 1 {
                        return place;
                    }
                }

                unreachable!()
            }

            ir::ExprKind::Num(_)
            | ir::ExprKind::Str(_)
            | ir::ExprKind::Bool(_)
            | ir::ExprKind::None
            | ir::ExprKind::Body(_)
            | ir::ExprKind::Let(_, _)
            | ir::ExprKind::Union(_)
            | ir::ExprKind::CallBody(_, _, _)
            | ir::ExprKind::Binary(_, _, _)
            | ir::ExprKind::Block(_)
            | ir::ExprKind::Record(_)
            | ir::ExprKind::Error => {
                let value = self.build_value(block, expr);
                let ty = self.build_type(&expr.ty);

                let index = self.locals.len();
                self.locals.push(ty);

                let place = mir::Place::local(index);
                self[*block].assign(place.clone(), value);

                place
            }
        }
    }

    fn build_operand(&mut self, block: &mut mir::BlockId, expr: &ir::Expr) -> mir::Operand {
        match expr.kind {
            ir::ExprKind::Num(value) => mir::Operand::Constant(mir::Constant::Num(value as f64)),

            ir::ExprKind::Bool(value) => mir::Operand::Constant(mir::Constant::Bool(value)),

            ir::ExprKind::Let(ref pattern, ref value) => {
                let place = self.build_place(block, value);
                self.build_pattern(block, pattern, &place);

                mir::Operand::NONE
            }

            ir::ExprKind::None => mir::Operand::NONE,

            ir::ExprKind::Promote(_, ref expr) => self.build_operand(block, expr),
            ir::ExprKind::Demote(_, ref expr) => self.build_operand(block, expr),

            ir::ExprKind::Block(ref exprs) => {
                for (i, expr) in exprs.iter().enumerate() {
                    let operand = self.build_operand(block, expr);

                    if i == exprs.len() - 1 {
                        return operand;
                    }
                }

                mir::Operand::NONE
            }

            ir::ExprKind::Str(_)
            | ir::ExprKind::Body(_)
            | ir::ExprKind::Local(_)
            | ir::ExprKind::Union(_)
            | ir::ExprKind::CallBody(_, _, _)
            | ir::ExprKind::Binary(_, _, _)
            | ir::ExprKind::Record(_)
            | ir::ExprKind::Error => {
                let place = self.build_place(block, expr);
                mir::Operand::Copy(place)
            }
        }
    }

    fn build_value(&mut self, block: &mut mir::BlockId, expr: &ir::Expr) -> mir::Value {
        match expr.kind {
            ir::ExprKind::Binary(op, ref lhs, ref rhs) => {
                let op = match op {
                    ir::BinOp::Add => mir::BinOp::Add,
                    ir::BinOp::Sub => mir::BinOp::Sub,
                    ir::BinOp::Mul => mir::BinOp::Mul,
                    ir::BinOp::Div => mir::BinOp::Div,
                    ir::BinOp::Mod => mir::BinOp::Mod,
                    ir::BinOp::Lt => mir::BinOp::Lt,
                    ir::BinOp::Gt => mir::BinOp::Gt,
                    ir::BinOp::Le => mir::BinOp::Le,
                    ir::BinOp::Ge => mir::BinOp::Ge,
                    ir::BinOp::Eq => todo!(),
                    ir::BinOp::Ne => todo!(),
                };

                let lhs = self.build_operand(block, lhs);
                let rhs = self.build_operand(block, rhs);

                mir::Value::Binary(op, lhs, rhs)
            }

            ir::ExprKind::Record(ref fields) => {
                let mut fields = fields.clone();
                fields.sort_by(|a, b| a.name.cmp(&b.name));

                let fields = fields
                    .iter()
                    .map(|f| self.build_operand(block, &f.expr))
                    .collect();

                mir::Value::Record(fields)
            }

            ir::ExprKind::Promote(_, ref expr) => self.build_value(block, expr),
            ir::ExprKind::Demote(_, ref expr) => self.build_value(block, expr),

            ir::ExprKind::Num(_)
            | ir::ExprKind::Str(_)
            | ir::ExprKind::Bool(_)
            | ir::ExprKind::None
            | ir::ExprKind::Body(_)
            | ir::ExprKind::Let(_, _)
            | ir::ExprKind::Local(_)
            | ir::ExprKind::Union(_)
            | ir::ExprKind::CallBody(_, _, _)
            | ir::ExprKind::Block(_)
            | ir::ExprKind::Error => {
                let operand = self.build_operand(block, expr);
                mir::Value::Use(operand)
            }
        }
    }
}

impl BlockBuilder {
    fn assign(&mut self, place: impl Into<mir::Place>, value: impl Into<mir::Value>) {
        self.statement(mir::Statement::Assign(place.into(), value.into()));
    }

    fn statement(&mut self, statement: mir::Statement) {
        self.statements.push(statement);
    }

    fn r#return(&mut self, value: mir::Value) {
        self.terminate(mir::Terminator::Return(value));
    }

    fn jump(&mut self, block: mir::BlockId) {
        self.terminate(mir::Terminator::Jump(block));
    }

    fn terminate(&mut self, terminator: mir::Terminator) {
        self.terminator = Some(terminator);
    }
}
