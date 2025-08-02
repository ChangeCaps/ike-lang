use std::collections::HashMap;

use crate::{ast, diagnostic::Diagnostic, ir::untyped as ir};

use super::{ExprLowerer, LowerError};

impl ExprLowerer<'_, '_> {
    pub(super) fn lower_pattern(
        &mut self,
        ast: ast::Pattern,
        ty: ir::Type,
    ) -> Result<ir::Pattern, LowerError> {
        Ok(match ast.kind {
            ast::PatternKind::Wildcard => ir::Pattern {
                kind: ir::PatternKind::Wildcard,
                span: ast.span,
            },

            ast::PatternKind::Path(path) => {
                if let Some(module) = self.ir.get_module(self.module, path.modules()) {
                    if let Some((tid, variant)) = self.ir[module].variants.get(path.name()).cloned()
                    {
                        let generics = self.ir.tcx[tid]
                            .generics
                            .iter()
                            .map(|(_, var)| ir::Type::infer(var.span()))
                            .collect::<Vec<_>>();

                        let union_ty = ir::Type::newtype(tid, generics, path.span);
                        self.unify(union_ty.clone(), ty, ast.span);

                        let kind = ir::PatternKind::Variant(union_ty, variant, None);
                        return Ok(ir::Pattern {
                            kind,
                            span: ast.span,
                        });
                    }
                }

                if path.segments().len() != 1 {
                    let diagnostic = Diagnostic::error(format!(
                        "invalid pattern path: '{path}', expected a single segment"
                    ))
                    .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                }

                let lid = self.body_mut().locals.push(ir::Local {
                    name: path.name().to_string(),
                    ty: ty.clone(),
                });

                self.scope.push(lid);

                ir::Pattern {
                    kind: ir::PatternKind::Binding(lid),
                    span: ast.span,
                }
            }

            ast::PatternKind::Variant(path, pattern) => {
                // get the module of the path
                let Some(module) = self.ir.get_module(self.module, path.modules()) else {
                    let diagnostic = Diagnostic::error(format!("unresolved module: {path}"))
                        .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                };

                // get the variant in the module
                let Some((tid, variant)) = self.ir[module].variants.get(path.name()).cloned()
                else {
                    let diagnostic = Diagnostic::error(format!("unresolved variant: {path}"))
                        .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                };

                // compute the generic paramters of the union
                let generics = self.ir.tcx[tid]
                    .generics
                    .iter()
                    .map(|(_, var)| ir::Type::infer(var.span()))
                    .collect::<Vec<_>>();

                // compute the generic substitution map
                let subst = self.ir.tcx[tid]
                    .generics
                    .iter()
                    .map(|(_, var)| *var)
                    .zip(generics.clone())
                    .collect::<HashMap<_, _>>();

                // get the underlying union type associtated with the variant in question
                let newtype = &self.ir.tcx[tid];
                let ir::NewtypeKind::Union(ref union) = newtype.kind else {
                    unreachable!();
                };

                // find the defined wrapped type of the variant
                //
                // i.e. type maybe-int = some-int int | no-int
                //           ^^^^^^^^^            ^^^ the wrapped type
                //                 | the union type
                let wrapped_ty = {
                    let variant = union
                        .variants
                        .iter()
                        .find(|v| v.name == variant)
                        .expect("variant not found in union");

                    match variant.ty {
                        Some(ref ty) => ty.clone().substitute(&subst).with_span(path.span),
                        None => {
                            let diagnostic = Diagnostic::error(format!(
                                "variant '{}' in union '{}' does not have a type",
                                variant.name, newtype.name
                            ));

                            self.lowerer.emitter.emit(diagnostic);
                            return Err(LowerError);
                        }
                    }
                };

                // unify the defined type of the union with the expected type
                let union_ty = ir::Type::newtype(tid, generics, path.span);
                self.unify(union_ty.clone(), ty, ast.span);

                // lower the pattern for the wrapped type
                let pattern = self.lower_pattern(*pattern, wrapped_ty)?;

                let kind = ir::PatternKind::Variant(union_ty, variant, Some(Box::new(pattern)));
                ir::Pattern {
                    kind,
                    span: ast.span,
                }
            }

            ast::PatternKind::Tuple(items) => {
                let mut types = Vec::new();
                let mut patterns = Vec::new();

                for item in items {
                    let item_ty = ir::Type::infer(item.span);
                    let item_pattern = self.lower_pattern(item, item_ty.clone())?;

                    types.push(item_ty);
                    patterns.push(item_pattern);
                }

                let tuple_ty = ir::Type::tuple(types, ast.span);
                self.unify(ty, tuple_ty, ast.span);

                ir::Pattern {
                    kind: ir::PatternKind::Tuple(patterns),
                    span: ast.span,
                }
            }

            ast::PatternKind::Bool(value) => {
                self.unify(ty, ir::Type::bool(ast.span), ast.span);

                ir::Pattern {
                    kind: ir::PatternKind::Bool(value),
                    span: ast.span,
                }
            }

            ast::PatternKind::Int(value) => {
                self.unify(ty, ir::Type::int(ast.span), ast.span);

                ir::Pattern {
                    kind: ir::PatternKind::Int(value),
                    span: ast.span,
                }
            }

            ast::PatternKind::String(value) => {
                self.unify(ty, ir::Type::str(ast.span), ast.span);

                ir::Pattern {
                    kind: ir::PatternKind::String(value),
                    span: ast.span,
                }
            }

            ast::PatternKind::List(items, rest) => {
                let item_ty = ir::Type::infer(ast.span);
                let list_ty = ir::Type::list(item_ty.clone(), ast.span);

                self.unify(ty, list_ty.clone(), ast.span);

                let mut pattern = match rest {
                    Some(rest) => self.lower_pattern(*rest, list_ty.clone())?,
                    None => ir::Pattern {
                        kind: ir::PatternKind::ListEmpty,
                        span: ast.span,
                    },
                };

                for item in items.into_iter().rev() {
                    let item_pattern = self.lower_pattern(item, item_ty.clone())?;

                    let span = item_pattern.span;
                    let kind = ir::PatternKind::ListCons(Box::new(item_pattern), Box::new(pattern));
                    pattern = ir::Pattern { kind, span };
                }

                pattern
            }
        })
    }
}
