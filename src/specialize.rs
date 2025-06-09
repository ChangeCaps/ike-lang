use std::collections::{BTreeMap, HashMap};

use crate::{
    diagnostic::Emitter,
    ir::{typed as tir, untyped as uir},
};

#[derive(Debug)]
pub struct SpecializeError;

pub fn specialize(
    uir: uir::Program,
    entry: uir::Bid,
    emitter: &mut dyn Emitter,
) -> Result<(tir::Program, tir::Bid), SpecializeError> {
    let mut specializer = Specializer {
        emitter,
        bodies: HashMap::new(),
        types: HashMap::new(),
        uir,
        tir: tir::Program::new(),
    };

    (specializer.uir.tcx)
        .finish(specializer.emitter)
        .map_err(|_| SpecializeError)?;

    let entry = specializer.specialize_body(entry, Default::default())?;

    Ok((specializer.tir, entry))
}

type Bodies = HashMap<(uir::Bid, BTreeMap<uir::Var, tir::Type>), tir::Bid>;
type Types = HashMap<(uir::Tid, Vec<tir::Type>), tir::Tid>;

struct Specializer<'a> {
    emitter: &'a mut dyn Emitter,
    bodies: Bodies,
    types: Types,
    uir: uir::Program,
    tir: tir::Program,
}

impl Specializer<'_> {
    fn specialize_body(
        &mut self,
        bid: uir::Bid,
        generics: BTreeMap<uir::Var, tir::Type>,
    ) -> Result<tir::Bid, SpecializeError> {
        let key = (bid, generics);

        if let Some(&bid) = self.bodies.get(&key) {
            return Ok(bid);
        }

        let (bid, generics) = key;

        let mut locals = tir::Locals::new();

        for local in self.uir[bid].locals.clone().values() {
            let ty = self.specialize_type(local.ty.clone(), &generics)?;

            locals.push(tir::Local {
                name: local.name.clone(),
                ty,
            });
        }

        let mut inputs = Vec::new();

        for input in self.uir[bid].inputs.clone() {
            inputs.push(self.specialize_pattern(input, &generics)?);
        }

        let ty = self.uir[bid].ty.clone();
        let ty = self.specialize_type(ty, &generics)?;

        let tir_bid = self.tir.bodies.push(tir::Body {
            name: self.uir[bid].name.clone(),
            locals,
            inputs,
            expr: None,
            ty,
        });

        self.bodies.insert((bid, generics.clone()), tir_bid);

        if let Some(body) = self.uir[bid].expr.clone() {
            let body = self.specialize_expr(body, &generics)?;
            self.tir.bodies[tir_bid].expr = Some(body);
        };

        Ok(tir_bid)
    }

    fn specialize_expr(
        &mut self,
        expr: uir::Expr,
        generics: &BTreeMap<uir::Var, tir::Type>,
    ) -> Result<tir::Expr, SpecializeError> {
        let expected = self.specialize_type(expr.ty, generics)?;

        let kind = match expr.kind {
            uir::ExprKind::Int(value) => tir::ExprKind::Int(value),
            uir::ExprKind::Bool(value) => tir::ExprKind::Bool(value),
            uir::ExprKind::String(value) => tir::ExprKind::String(value),
            uir::ExprKind::Local(lid) => tir::ExprKind::Local(lid.cast()),

            uir::ExprKind::Body(bid) => {
                let ty = self.uir.tcx.substitute(self.uir[bid].ty.clone());
                let generics = Self::extract_generics(ty, expected.clone());
                let bid = self.specialize_body(bid, generics)?;

                tir::ExprKind::Body(bid)
            }

            uir::ExprKind::Let(pattern, value) => {
                let pattern = self.specialize_pattern(pattern, generics)?;
                let value = self.specialize_expr(*value, generics)?;

                tir::ExprKind::Let(pattern, Box::new(value))
            }

            uir::ExprKind::Variant(name, value) => {
                let value = match value {
                    Some(value) => Some(Box::new(self.specialize_expr(*value, generics)?)),
                    None => None,
                };

                tir::ExprKind::Variant(name, value)
            }

            uir::ExprKind::Call(target, input) => {
                let target = self.specialize_expr(*target, generics)?;
                let input = self.specialize_expr(*input, generics)?;

                tir::ExprKind::Call(Box::new(target), Box::new(input))
            }

            uir::ExprKind::ListEmpty => tir::ExprKind::ListEmpty,

            uir::ExprKind::ListCons(head, tail) => {
                let head = self.specialize_expr(*head, generics)?;
                let tail = self.specialize_expr(*tail, generics)?;

                tir::ExprKind::ListCons(Box::new(head), Box::new(tail))
            }

            uir::ExprKind::Tuple(exprs) => {
                let mut new_exprs = Vec::new();

                for expr in exprs {
                    let expr = self.specialize_expr(expr, generics)?;
                    new_exprs.push(expr);
                }

                tir::ExprKind::Tuple(new_exprs)
            }

            uir::ExprKind::Record(fields) => {
                let mut new_fields = Vec::new();

                for (name, expr) in fields {
                    let expr = self.specialize_expr(expr, generics)?;
                    new_fields.push((name, expr));
                }

                tir::ExprKind::Record(new_fields)
            }

            uir::ExprKind::Binary(op, lhs, rhs) => {
                let left = self.specialize_expr(*lhs, generics)?;
                let right = self.specialize_expr(*rhs, generics)?;

                tir::ExprKind::Binary(op, Box::new(left), Box::new(right))
            }

            uir::ExprKind::Field(target, name) => {
                let target = self.specialize_expr(*target, generics)?;

                tir::ExprKind::Field(Box::new(target), name)
            }

            uir::ExprKind::Match(target, arms) => {
                let target = self.specialize_expr(*target, generics)?;

                let mut new_arms = Vec::new();
                for arm in arms {
                    let pattern = self.specialize_pattern(arm.pattern, generics)?;
                    let expr = self.specialize_expr(arm.expr, generics)?;
                    new_arms.push(tir::Arm { pattern, expr });
                }

                tir::ExprKind::Match(Box::new(target), new_arms)
            }

            uir::ExprKind::Block(exprs) => {
                let mut new_exprs = Vec::new();

                for expr in exprs {
                    let expr = self.specialize_expr(expr, generics)?;
                    new_exprs.push(expr);
                }

                tir::ExprKind::Block(new_exprs)
            }
        };

        let expr = tir::Expr {
            kind,
            span: expr.span,
            ty: expected,
        };

        Ok(expr)
    }

    fn specialize_pattern(
        &mut self,
        pattern: uir::Pattern,
        generics: &BTreeMap<uir::Var, tir::Type>,
    ) -> Result<tir::Pattern, SpecializeError> {
        let kind = match pattern.kind {
            uir::PatternKind::Wildcard => tir::PatternKind::Wildcard,
            uir::PatternKind::Binding(lid) => tir::PatternKind::Binding(lid.cast()),

            uir::PatternKind::Tuple(patterns) => {
                let mut new_patterns = Vec::new();

                for pattern in patterns {
                    let pattern = self.specialize_pattern(pattern, generics)?;
                    new_patterns.push(pattern);
                }

                tir::PatternKind::Tuple(new_patterns)
            }

            uir::PatternKind::Bool(value) => tir::PatternKind::Bool(value),

            uir::PatternKind::Variant(ty, name, value) => {
                let ty = self.specialize_type(ty, generics)?;

                let value = match value {
                    Some(value) => Some(Box::new(self.specialize_pattern(*value, generics)?)),
                    None => None,
                };

                tir::PatternKind::Variant(ty, name, value)
            }

            uir::PatternKind::ListEmpty => tir::PatternKind::ListEmpty,
            uir::PatternKind::ListCons(head, tail) => {
                let head = self.specialize_pattern(*head, generics)?;
                let tail = self.specialize_pattern(*tail, generics)?;

                tir::PatternKind::ListCons(Box::new(head), Box::new(tail))
            }
        };

        Ok(tir::Pattern {
            kind,
            span: pattern.span,
        })
    }

    fn specialize_type(
        &mut self,
        ty: uir::Type,
        generics: &BTreeMap<uir::Var, tir::Type>,
    ) -> Result<tir::Type, SpecializeError> {
        match self.uir.tcx.substitute(ty) {
            uir::Type::Var(var) => match generics.get(&var) {
                Some(ty) => Ok(ty.clone()),
                None => Ok(tir::Type::Unit),
            },

            uir::Type::App(app) => Ok(match app {
                uir::App::Int => tir::Type::Int,
                uir::App::Str => tir::Type::Str,
                uir::App::Bool => tir::Type::Bool,
                uir::App::Unit => tir::Type::Unit,

                uir::App::List(item) => {
                    let item = self.specialize_type(*item, generics)?;
                    tir::Type::List(Box::new(item))
                }

                uir::App::Tuple(fields) => {
                    let fields = fields
                        .into_iter()
                        .map(|ty| self.specialize_type(ty, generics))
                        .collect::<Result<Vec<_>, _>>()?;

                    tir::Type::Tuple(fields)
                }

                uir::App::Newtype(tid, arguments) => {
                    let arguments = arguments
                        .into_iter()
                        .map(|ty| self.specialize_type(ty, generics))
                        .collect::<Result<Vec<_>, _>>()?;

                    let tid = self.specialize_newtype(tid, arguments.clone())?;
                    tir::Type::Newtype(tid, arguments)
                }

                uir::App::Function(input, output) => {
                    let input = self.specialize_type(*input, generics)?;
                    let output = self.specialize_type(*output, generics)?;

                    tir::Type::Function(Box::new(input), Box::new(output))
                }
            }),
        }
    }

    fn specialize_newtype(
        &mut self,
        tid: uir::Tid,
        arguments: Vec<tir::Type>,
    ) -> Result<tir::Tid, SpecializeError> {
        if let Some(&tid) = self.types.get(&(tid, arguments.clone())) {
            return Ok(tid);
        }

        let newtype = &self.uir.tcx[tid];

        let generics: BTreeMap<_, _> = newtype
            .generics
            .iter()
            .map(|(_, var)| *var)
            .zip(arguments.clone())
            .collect();

        match newtype.kind {
            uir::NewtypeKind::Record(ref record) => {
                let tir_tid = self
                    .tir
                    .types
                    .push_newtype(tir::Newtype::Record(tir::Record::default()));

                self.types.insert((tid, arguments), tir_tid);

                let mut fields = Vec::new();

                for field in record.fields.clone() {
                    let ty = self.specialize_type(field.ty.clone(), &generics)?;
                    fields.push(tir::Field {
                        name: field.name.clone(),
                        ty,
                    });
                }

                let record = tir::Record { fields };
                self.tir.types[tir_tid] = tir::Newtype::Record(record);

                Ok(tir_tid)
            }

            uir::NewtypeKind::Union(ref union) => {
                let tir_tid = self
                    .tir
                    .types
                    .push_newtype(tir::Newtype::Union(tir::Union::default()));

                self.types.insert((tid, arguments), tir_tid);

                let mut variants = Vec::new();

                for variant in union.variants.clone() {
                    let ty = match variant.ty {
                        Some(ty) => Some(self.specialize_type(ty, &generics)?),
                        None => None,
                    };

                    variants.push(tir::Variant {
                        name: variant.name.clone(),
                        ty,
                    });
                }

                let union = tir::Union { variants };
                self.tir.types[tir_tid] = tir::Newtype::Union(union);

                Ok(tir_tid)
            }
        }
    }

    fn extract_generics(ty: uir::Type, expected: tir::Type) -> BTreeMap<uir::Var, tir::Type> {
        let mut generics = BTreeMap::new();
        Self::extract_generics_impl(ty, expected, &mut generics);
        generics
    }

    fn extract_generics_impl(
        ty: uir::Type,
        expected: tir::Type,
        generics: &mut BTreeMap<uir::Var, tir::Type>,
    ) {
        match ty {
            uir::Type::Var(var) => {
                if let Some(existing) = generics.get(&var) {
                    assert_eq!(*existing, expected);
                }

                generics.insert(var, expected);
            }

            uir::Type::App(app) => match (app, expected) {
                (uir::App::Int, tir::Type::Int)
                | (uir::App::Str, tir::Type::Str)
                | (uir::App::Bool, tir::Type::Bool)
                | (uir::App::Unit, tir::Type::Unit) => {}

                (uir::App::List(ty), tir::Type::List(expected)) => {
                    Self::extract_generics_impl(*ty, *expected, generics);
                }

                (uir::App::Tuple(tys), tir::Type::Tuple(expected)) => {
                    for (ty, expected) in tys.into_iter().zip(expected) {
                        Self::extract_generics_impl(ty, expected, generics);
                    }
                }

                (uir::App::Function(input, output), tir::Type::Function(e_input, e_output)) => {
                    Self::extract_generics_impl(*input, *e_input, generics);
                    Self::extract_generics_impl(*output, *e_output, generics);
                }

                (uir::App::Newtype(_, args), tir::Type::Newtype(_, expected_args)) => {
                    for (arg, expected_arg) in args.into_iter().zip(expected_args) {
                        Self::extract_generics_impl(arg, expected_arg, generics);
                    }
                }

                (_, _) => panic!(),
            },
        }
    }
}
