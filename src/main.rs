use std::{
    collections::HashSet,
    env,
    error::Error,
    fs::{self, File},
    path::{Path, PathBuf},
    process::{self, Command, Stdio},
};

use clap::{Parser, Subcommand};
use ike::{
    ast,
    diagnostic::{self, Emitter},
    ir, lower, lsp, lua, parse, specialize,
};

#[derive(Parser)]
struct Args {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Run the language server.
    Lsp,

    Run(RunArgs),
}

#[derive(Parser)]
struct RunArgs {
    package: Option<PathBuf>,
}

#[derive(Debug)]
struct BuildOptions {
    packages: Vec<Package>,
}

impl BuildOptions {
    fn verify(&self) -> Result<(), Box<dyn Error>> {
        let mut binary = None;
        let mut names = HashSet::new();

        for package in &self.packages {
            if package.kind == PackageKind::Binary {
                if let Some(binary) = binary {
                    return Err(From::from(format!(
                        "build cannot have two binary packages, `{}` and `{}`",
                        binary, package.name,
                    )));
                }

                binary = Some(&package.name);
            }

            if !names.insert(&package.name) {
                return Err(From::from(format!(
                    "build has multiple packages with the name `{}`",
                    package.name,
                )));
            }
        }

        if binary.is_none() {
            return Err(From::from("build has must have a binary package"));
        }

        Ok(())
    }

    fn binary(&self) -> Option<&Package> {
        self.packages.iter().find(|p| p.kind == PackageKind::Binary)
    }
}

#[derive(Debug)]
struct Package {
    path: PathBuf,
    name: String,
    kind: PackageKind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PackageKind {
    Library,
    Binary,
}

fn main() -> Result<(), Box<dyn Error>> {
    let args = Args::parse();

    match args.command {
        Commands::Lsp => lsp::LanguageServer::new()?.run(),
        Commands::Run(args) => {
            let target_path = args.package.unwrap();
            let target_name = target_path
                .file_stem()
                .unwrap()
                .to_string_lossy()
                .to_string();

            let options = BuildOptions {
                packages: vec![
                    Package {
                        path: PathBuf::from("std"),
                        name: String::from("std"),
                        kind: PackageKind::Library,
                    },
                    Package {
                        path: target_path,
                        name: target_name,
                        kind: PackageKind::Binary,
                    },
                ],
            };

            options.verify()?;

            let mut sources = diagnostic::Sources::new();
            let mut emitter = Vec::new();

            if let Err(err) = compile(&mut sources, &mut emitter, &options) {
                for diagnostic in emitter {
                    diagnostic.print(&sources);
                }

                println!("{err}");

                process::exit(1);
            }

            Command::new("lua")
                .arg("test.lua")
                .args(env::args())
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .output()?;

            Ok(())
        }
    }
}

#[allow(unused)]
fn lower(
    sources: &mut diagnostic::Sources,
    emitter: &mut dyn Emitter,
    options: &BuildOptions,
) -> Result<ir::untyped::Program, Box<dyn Error>> {
    let mut lowerer = lower::Lowerer::new(emitter);

    for package in &options.packages {
        let module = match package.path.is_dir() {
            true => parse_directory(sources, lowerer.emitter(), &package.path)?,
            false => {
                let file = parse_file(sources, lowerer.emitter(), &package.path)?;

                let mut module = ast::Module::new();
                module.files.insert(package.name.clone(), file);

                module
            }
        };

        lowerer.add_module(&[&package.name], &module)?;
    }

    lowerer.finish().map_err(From::from)
}

fn compile(
    sources: &mut diagnostic::Sources,
    emitter: &mut dyn Emitter,
    options: &BuildOptions,
) -> Result<(), Box<dyn Error>> {
    let ir = lower(sources, emitter, options)?;

    let binary = options.binary().unwrap();

    let ike = ir[ir.root].modules[&binary.name];
    let entry = ir[ike]
        .bodies
        .get("main")
        .copied()
        .ok_or_else(|| -> Box<dyn Error> {
            From::from(format!(
                "module `{}` does not have a function `main`",
                binary.name
            ))
        })?;

    let (ir, entry) = specialize::specialize(ir, entry, emitter)?;

    let mut file = File::create("test.lua")?;
    lua::codegen(&mut file, &ir, entry)?;

    Ok(())
}

fn parse_directory(
    sources: &mut diagnostic::Sources,
    emitter: &mut dyn Emitter,
    path: impl AsRef<Path>,
) -> Result<ast::Module, Box<dyn Error>> {
    let mut module = ast::Module::new();

    for entry in fs::read_dir(path).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();

        let name = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap()
            .to_string();

        if path.is_dir() {
            let submodule = parse_directory(sources, emitter, &path)?;
            module.modules.insert(name, submodule);
        } else if path.extension().and_then(|s| s.to_str()) == Some("ike") {
            let file = parse_file(sources, emitter, path)?;
            module.files.insert(name, file);
        }
    }

    Ok(module)
}

fn parse_file(
    sources: &mut diagnostic::Sources,
    emitter: &mut dyn Emitter,
    path: impl AsRef<Path>,
) -> Result<ast::File, Box<dyn Error>> {
    let content = fs::read_to_string(&path).unwrap();

    let source = diagnostic::Source {
        path: path.as_ref().to_path_buf(),
        content,
    };

    let sid = sources.add(source);
    let input = &sources[sid].content;

    let mut tokens = parse::tokenize(input, sid, emitter).map_err(|_| "tokenize error")?;
    let file = parse::parse_file(&mut tokens, emitter).map_err(|_| "parse error")?;

    Ok(file)
}
