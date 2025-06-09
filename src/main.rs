use std::{env, fs, path::Path, process::Command};

use ike::{
    codegen,
    diagnostic::{DebugEmitter, Sid},
    lower,
    parse::{parse_module, tokenize},
    specialize,
};

fn main() {
    let mut emitter = DebugEmitter;

    let mut lowerer = lower::Lowerer::new(&mut emitter);

    add_directory(&mut lowerer, &["std"], "std");
    add_directory(&mut lowerer, &["ike"], "ike");

    let ir = lowerer.finish().unwrap();

    let ike = ir[ir.root].modules["ike"];
    let entry = ir[ike].bodies["main"];

    let (ir, entry) = specialize::specialize(ir, entry, &mut emitter).unwrap();

    let code = codegen::codegen(&ir, entry);
    fs::write("test.lua", code).unwrap();

    Command::new("lua")
        .arg("test.lua")
        .args(env::args())
        .status()
        .expect("Failed to execute Lua script");
}

fn add_directory(lowerer: &mut lower::Lowerer, modules: &[&str], path: impl AsRef<Path>) {
    for entry in fs::read_dir(path).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();

        if path.is_dir() {
            let name = path.file_name().and_then(|s| s.to_str()).unwrap();

            let mut new_modules = modules.to_vec();
            new_modules.push(name);

            lowerer.create_module(new_modules.iter().copied());

            add_directory(lowerer, &new_modules, &path);
        } else if path.extension().and_then(|s| s.to_str()) == Some("ike") {
            let input = fs::read_to_string(&path).unwrap();
            let mut tokens = tokenize(&input, Sid(0)).unwrap();
            let module = parse_module(&mut tokens).unwrap();

            lowerer.add_module(modules, module).unwrap();
        }
    }
}
