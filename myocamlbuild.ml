open Ocamlbuild_plugin
open Command
open Arch
open Format

module C = Myocamlbuild_config

let windows = Sys.os_type = "Win32";;
if windows then tag_any ["windows"];;
let ccomptype = C.ccomptype
let () = if ccomptype <> "cc" then eprintf "ccomptype: %s@." ccomptype;;

let fp_cat oc f = with_input_file ~bin:true f (fun ic -> copy_chan ic oc)

(* Improve using the command module in Myocamlbuild_config
   with the variant version (`S, `A...) *)
let mkdll out implib files opts =
  let s = Command.string_of_command_spec in
  Cmd(Sh(C.mkdll out (s implib) (s files) (s opts)))

let mkexe out files opts =
  let s = Command.string_of_command_spec in
  Cmd(Sh(C.mkexe out (s files) (s opts)))

let mklib out files opts =
  let s = Command.string_of_command_spec in
  Cmd(Sh(C.mklib out (s files) (s opts)))  

let syslib x = A(C.syslib x);;
let syscamllib x =
  if ccomptype = "msvc" then A(Printf.sprintf "lib%s.lib" x)
  else A("-l"^x)

let mkobj obj file opts =
  let obj = obj-.-C.o in
  if ccomptype = "msvc" then
    Seq[Cmd(S[Sh C.bytecc; Sh C.bytecccompopts; opts; A"-c"; Px file]);
        mv (Pathname.basename (Pathname.update_extension C.o file)) obj]
  else
    Cmd(S[Sh C.bytecc; Sh C.bytecccompopts; opts; A"-c"; P file; A"-o"; Px obj])

let mkdynobj obj file opts =
  let d_obj = obj-.-"d"-.-C.o in
  if ccomptype = "msvc" then
    Seq[Cmd(S[Sh C.bytecc; opts; Sh C.dllcccompopts; A"-c"; Px file]);
        mv (Pathname.basename (Pathname.update_extension C.o file)) d_obj]
  else
    Cmd(S[Sh C.bytecc; opts; Sh C.dllcccompopts; A"-c"; P file; A"-o"; Px d_obj])

let mknatobj obj file opts =
  let obj = obj-.-C.o in
  if ccomptype = "msvc" then
    Seq[Cmd(S[Sh C.nativecc; opts; A"-c"; Px file]);
        mv (Pathname.basename (Pathname.update_extension C.o file)) obj]
  else
    Cmd(S[Sh C.nativecc; A"-O"; opts;
          Sh C.nativecccompopts; A"-c"; P file; A"-o"; Px obj])

let add_exe a =
  if not windows || Pathname.check_extension a "exe" then a
  else a-.-"exe";;

let add_exe_if_exists a =
  if not windows || Pathname.check_extension a "exe" then a
  else
    let exe = a-.-"exe" in
    if Pathname.exists exe then exe else a;;

let convert_command_for_windows_shell spec =
  if not windows then spec else 
  let rec self specs acc =
    match specs with
    | N :: specs -> self specs acc
    | S[] :: specs -> self specs acc
    | S[x] :: specs -> self (x :: specs) acc
    | S specs :: specs' -> self (specs @ specs') acc
    | (P(a) | A(a)) :: specs ->
        let dirname = Pathname.dirname a in
        let basename = Pathname.basename a in
        let p =
          if dirname = Pathname.current_dir_name then Sh(add_exe_if_exists basename)
          else Sh(add_exe_if_exists (dirname ^ "\\" ^ basename)) in
        if String.contains_string basename 0 "ocamlrun" = None then
          List.rev (p :: acc) @ specs
        else
          self specs (p :: acc)
    | [] | (Px _ | T _ | V _ | Sh _ | Quote _) :: _ ->
        invalid_arg "convert_command_for_windows_shell: invalid atom in head position"
  in S(self [spec] [])

let convert_for_windows_shell solver () =
  convert_command_for_windows_shell (solver ())

let ocamlrun = A"boot/ocamlrun"
let full_ocamlrun = P((Sys.getcwd ()) / "boot/ocamlrun")

let boot_ocamlc = S[ocamlrun; A"boot/ocamlc"; A"-I"; A"boot"; A"-nostdlib"]

let partial = bool_of_string (getenv ~default:"false" "OCAMLBUILD_PARTIAL");;

let if_partial_dir dir =
  if partial then ".."/dir else dir;;

let unix_dir =
  match Sys.os_type with
  | "Win32" -> if_partial_dir "otherlibs/win32unix"
  | _       -> if_partial_dir "otherlibs/unix";;

let threads_dir    = if_partial_dir "otherlibs/threads";;
let systhreads_dir = if_partial_dir "otherlibs/systhreads";;
let dynlink_dir    = if_partial_dir "otherlibs/dynlink";;
let str_dir        = if_partial_dir "otherlibs/str";;
let toplevel_dir   = if_partial_dir "toplevel";;

let ocamlc_solver =
  let native_deps = ["ocamlc.opt"; "stdlib/stdlib.cmxa";
                    "stdlib/std_exit.cmx"; "stdlib/std_exit"-.-C.o] in
  let byte_deps = ["ocamlc"; "stdlib/stdlib.cma"; "stdlib/std_exit.cmo"] in
  fun () ->
    if List.for_all Pathname.exists native_deps then
      S[A"./ocamlc.opt"; A"-nostdlib"]
    else if List.for_all Pathname.exists byte_deps then
      S[ocamlrun; A"./ocamlc"; A"-nostdlib"]
    else boot_ocamlc;;

Command.setup_virtual_command_solver "OCAMLC" ocamlc_solver;;
Command.setup_virtual_command_solver "OCAMLCWIN" (convert_for_windows_shell ocamlc_solver);;

let ocamlopt_solver () =
  S[if Pathname.exists "ocamlopt.opt" && Pathname.exists ("stdlib/stdlib.cmxa")
    then A"./ocamlopt.opt"
    else S[ocamlrun; A"./ocamlopt"];
    A"-nostdlib"];;

Command.setup_virtual_command_solver "OCAMLOPT" ocamlopt_solver;;
Command.setup_virtual_command_solver "OCAMLOPTWIN" (convert_for_windows_shell ocamlopt_solver);;

let ocamlc   = V"OCAMLC";;
let ocamlopt = V"OCAMLOPT";;

let ar = A"ar";;

dispatch begin function
| Before_hygiene ->
    if partial then
      let patt = String.concat ","
        ["asmcomp"; "bytecomp"; "debugger"; "driver";
         "lex"; "ocamldoc"; "otherlibs"; "parsing"; "stdlib"; "tools";
         "toplevel"; "typing"; "utils"]
      in Ocamlbuild_pack.Configuration.parse_string
           (sprintf "<{%s}/**>: not_hygienic, -traverse" patt)
  
| After_options ->
    begin
      Options.ocamlrun := ocamlrun;
      Options.ocamllex := S[ocamlrun; P"boot/ocamllex"];
      Options.ocamlyacc := if windows then P"./boot/ocamlyacc.exe" else P"boot/ocamlyacc";
      Options.ocamlmklib := S[ocamlrun; P"tools/ocamlmklib.byte"; A"-ocamlc"; Quote (V"OCAMLCWIN");
                              A"-ocamlopt"; Quote (V"OCAMLOPTWIN")(* ; A"-v" *)];
      Options.ocamldep := S[ocamlrun; P"boot/ocamldep"];

      Options.ext_obj := C.o;
      Options.ext_lib := C.a;
      Options.ext_dll := String.after C.ext_dll 1;

      Options.nostdlib := true;
      Options.make_links := false;
      if !Options.just_plugin then
        Options.ocamlc := boot_ocamlc
      else begin
        Options.ocamlc := ocamlc;
        Options.plugin := false;
        Options.ocamlopt := ocamlopt;
      end;
    end
| After_rules ->
    let module M = struct



let hot_camlp4boot = "camlp4"/"boot"/"camlp4boot.byte";;
let cold_camlp4boot = "camlp4boot" (* The installed version *);;

flag ["ocaml"; "ocamlyacc"] (A"-v");;

flag ["ocaml"; "compile"; "warn_Ale"] (S[A"-w";A"Ale"; A"-warn-error";A"Ale"]);;
flag ["ocaml"; "compile"; "warn_Alezv"] (S[A"-w";A"Alezv"; A"-warn-error";A"Alezv"]);;

non_dependency "otherlibs/threads/pervasives.ml" "Unix";;
non_dependency "otherlibs/threads/pervasives.ml" "String";;

let add_extensions extensions modules =
  List.fold_right begin fun x ->
    List.fold_right begin fun ext acc ->
      x-.-ext :: acc
    end extensions
  end modules [];;

flag ["ocaml"; "pp"; "camlp4boot"] (convert_command_for_windows_shell (S[ocamlrun; P hot_camlp4boot]));;
flag ["ocaml"; "pp"; "camlp4boot"; "native"] (S[A"-D"; A"OPT"]);;
flag ["ocaml"; "pp"; "camlp4boot"; "ocamldep"] (S[A"-D"; A"OPT"]);;
let exn_tracer = Pathname.pwd/"camlp4"/"boot"/"Camlp4ExceptionTracer.cmo" in
if Pathname.exists exn_tracer then
  flag ["ocaml"; "pp"; "camlp4boot"; "exntracer"] (P exn_tracer);

use_lib "camlp4/mkcamlp4" "camlp4/camlp4lib";;
use_lib "toplevel/topstart" "toplevel/toplevellib";;
use_lib "otherlibs/dynlink/extract_crc" "otherlibs/dynlink/dynlink";;

hide_package_contents "otherlibs/dynlink/dynlinkaux";;

flag ["ocaml"; "link"; "file:driver/main.native"; "native"] begin
  S[A"-ccopt"; A C.bytecclinkopts; A"-cclib"; A C.bytecclibs]
end;;

dep ["ocaml"; "link"; "file:driver/main.native"; "native"]
    ["asmrun/meta"-.-C.o; "asmrun/dynlink"-.-C.o];;

dep ["ocaml"; "compile"; "native"] ["stdlib/libasmrun"-.-C.a];;

flag ["ocaml"; "link"] (S[A"-I"; P "stdlib"]);;
flag ["ocaml"; "compile"; "include_unix"] (S[A"-I"; P unix_dir]);;
flag ["ocaml"; "compile"; "include_str"] (S[A"-I"; P str_dir]);;
flag ["ocaml"; "compile"; "include_dynlink"] (S[A"-I"; P dynlink_dir]);;
flag ["ocaml"; "compile"; "include_toplevel"] (S[A"-I"; P toplevel_dir]);;
flag ["ocaml"; "link"; "use_unix"] (S[A"-I"; P unix_dir]);;
flag ["ocaml"; "link"; "use_dynlink"] (S[A"-I"; P dynlink_dir]);;
flag ["ocaml"; "link"; "use_str"] (S[A"-I"; P str_dir]);;
flag ["ocaml"; "link"; "use_toplevel"] (S[A"-I"; P toplevel_dir]);;

let setup_arch arch =
  let annotated_arch = annotate arch in
  let (_include_dirs_table, _for_pack_table) = mk_tables annotated_arch in
  (* Format.eprintf "%a@." (Ocaml_arch.print_table (List.print pp_print_string)) include_dirs_table;; *)
  iter_info begin fun i ->
    Pathname.define_context i.current_path i.include_dirs
  end annotated_arch;;

let camlp4_arch =
  dir "" [
    dir "stdlib" [];
    dir "camlp4" [
      dir "build" [];
      dir_pack "Camlp4" [
        dir_pack "Struct" [
          dir_pack "Grammar" [];
        ];
        dir_pack "Printers" [];
      ];
      dir_pack "Camlp4Top" [];
    ];
  ];;

setup_arch camlp4_arch;;

Pathname.define_context "" ["stdlib"];;
Pathname.define_context "utils" [Pathname.current_dir_name; "stdlib"];;
Pathname.define_context "camlp4" ["camlp4"; "stdlib"];;
Pathname.define_context "camlp4/boot" ["camlp4"; "stdlib"];;
Pathname.define_context "camlp4/Camlp4Parsers" ["camlp4"; "stdlib"];;
Pathname.define_context "camlp4/Camlp4Printers" ["camlp4"; "stdlib"];;
Pathname.define_context "camlp4/Camlp4Filters" ["camlp4"; "stdlib"];;
Pathname.define_context "camlp4/Camlp4Top" ["camlp4"; "stdlib"];;
Pathname.define_context "parsing" ["parsing"; "utils"; "stdlib"];;
Pathname.define_context "typing" ["typing"; "parsing"; "utils"; "stdlib"];;
Pathname.define_context "ocamldoc" ["typing"; "parsing"; "utils"; "tools"; "bytecomp"; "stdlib"];;
Pathname.define_context "bytecomp" ["bytecomp"; "parsing"; "typing"; "utils"; "stdlib"];;
Pathname.define_context "tools" ["tools"; (* "toplevel"; *) "parsing"; "utils"; "driver"; "bytecomp"; "asmcomp"; "typing"; "stdlib"];;
Pathname.define_context "toplevel" ["toplevel"; "parsing"; "typing"; "bytecomp"; "utils"; "driver"; "stdlib"];;
Pathname.define_context "driver" ["driver"; "asmcomp"; "bytecomp"; "typing"; "utils"; "parsing"; "stdlib"];;
Pathname.define_context "debugger" ["bytecomp"; "utils"; "typing"; "parsing"; "toplevel"; "stdlib"];;
Pathname.define_context "otherlibs/dynlink" ["otherlibs/dynlink"; "bytecomp"; "utils"; "typing"; "parsing"; "stdlib"];;
Pathname.define_context "asmcomp" ["asmcomp"; "bytecomp"; "parsing"; "typing"; "utils"; "stdlib"];;
Pathname.define_context "ocamlbuild" ["ocamlbuild"; "stdlib"; "."];;
Pathname.define_context "lex" ["lex"; "stdlib"];;

List.iter (fun x -> let x = "otherlibs"/x in Pathname.define_context x [x; "stdlib"])
  ["bigarray"; "dbm"; "graph"; "num"; "str"; "systhreads"; "unix"; "win32graph"; "win32unix"];;

(* The bootstrap standard library *)
copy_rule "The bootstrap standard library" "stdlib/%" "boot/%";;

(* About the standard library *)
copy_rule "stdlib asmrun"  ("asmrun/%"-.-C.a)  ("stdlib/%"-.-C.a);;
copy_rule "stdlib byterun" ("byterun/%"-.-C.a) ("stdlib/%"-.-C.a);;

(* The thread specific standard library *)
copy_rule "The thread specific standard library (mllib)" ~insert:`bottom "stdlib/%.mllib" "otherlibs/threads/%.mllib";;
copy_rule "The thread specific standard library (cmo)"   ~insert:`bottom "stdlib/%.cmo" "otherlibs/threads/%.cmo";;
copy_rule "The thread specific standard library (cmi)"   ~insert:`top    "stdlib/%.cmi" "otherlibs/threads/%.cmi";;
copy_rule "The thread specific standard library (mli)"   ~insert:`bottom "stdlib/%.mli" "otherlibs/threads/%.mli";;
copy_rule "The thread specific unix library (mli)"       ~insert:`bottom "otherlibs/unix/%.mli" "otherlibs/threads/%.mli";;
copy_rule "The thread specific unix library (ml)"        ~insert:`bottom "otherlibs/unix/%.ml" "otherlibs/threads/%.ml";;
copy_rule "The thread specific unix library (mllib)"     ~insert:`bottom "otherlibs/unix/%.mllib" "otherlibs/threads/%.mllib";;

(* Temporary rule, waiting for a full usage of ocamlbuild *)
copy_rule "Temporary rule, waiting for a full usage of ocamlbuild" "%.mlbuild" "%.ml";;

if windows then
  copy_rule "thread_win32.ml -> thread.ml"
    "otherlibs/systhreads/thread_win32.ml" "otherlibs/systhreads/thread.ml"
else
  copy_rule "thread_posix.ml -> thread.ml"
    "otherlibs/systhreads/thread_posix.ml" "otherlibs/systhreads/thread.ml";;

copy_rule "graph/graphics.ml -> win32graph/graphics.ml" "otherlibs/graph/graphics.ml" "otherlibs/win32graph/graphics.ml";;
copy_rule "graph/graphics.mli -> win32graph/graphics.mli" "otherlibs/graph/graphics.mli" "otherlibs/win32graph/graphics.mli";;

rule "the ocaml toplevel"
  ~prod:"ocaml"
  ~deps:["stdlib/stdlib.mllib"; "toplevel/topstart.byte"; "toplevel/expunge.byte"]
  begin fun _ _ ->
    let modules = string_list_of_file "stdlib/stdlib.mllib" in
    Cmd(S[ocamlrun; A"toplevel/expunge.byte"; A"toplevel/topstart.byte"; Px"ocaml";
          A"outcometree"; A"topdirs"; A"toploop"; atomize modules])
  end;;

let copy_rule' ?insert src dst = copy_rule (sprintf "%s -> %s" src dst) ?insert src dst;;

copy_rule' "driver/main.byte" "ocamlc";;
copy_rule' "driver/main.native" "ocamlc.opt";;
copy_rule' "driver/optmain.byte" "ocamlopt";;
copy_rule' "driver/optmain.native" "ocamlopt.opt";;
copy_rule' "lex/main.byte" "lex/ocamllex";;
copy_rule' "lex/main.native" "lex/ocamllex.opt";;
copy_rule' "debugger/main.byte" "debugger/ocamldebug";;
copy_rule' "ocamldoc/odoc.byte" "ocamldoc/ocamldoc";;
copy_rule' "ocamldoc/odoc_opt.native" "ocamldoc/ocamldoc.opt";;
copy_rule' "tools/ocamlmklib.byte" "tools/ocamlmklib";;
copy_rule' "otherlibs/dynlink/extract_crc.byte" "otherlibs/dynlink/extract_crc";;

copy_rule' ~insert:`bottom "%" "%.exe";;

ocaml_lib "stdlib/stdlib";;

let stdlib_mllib_contents =
  lazy (string_list_of_file "stdlib/stdlib.mllib");;

let import_stdlib_contents build exts =
  let l =
    List.fold_right begin fun x ->
      List.fold_right begin fun ext acc ->
        ["stdlib"/(String.uncapitalize x)-.-ext] :: acc
      end exts
    end !*stdlib_mllib_contents []
  in
  let res = build l in
  List.iter Outcome.ignore_good res
;;

rule "byte stdlib in partial mode"
  ~prod:"byte_stdlib_partial_mode"
  ~deps:["stdlib/stdlib.mllib"; "stdlib/stdlib.cma";
         "stdlib/std_exit.cmo"; "stdlib/libcamlrun"-.-C.a;
         "stdlib/camlheader"; "stdlib/camlheader_ur"]
  begin fun env build ->
    let (_ : Command.t) =
      Ocamlbuild_pack.Ocaml_compiler.byte_library_link_mllib
        "stdlib/stdlib.mllib" "stdlib/stdlib.cma" env build
    in
    import_stdlib_contents build ["cmi"];
    touch "byte_stdlib_partial_mode"
  end;;

rule "native stdlib in partial mode"
  ~prod:"native_stdlib_partial_mode"
  ~deps:["stdlib/stdlib.mllib"; "stdlib/stdlib.cmxa";
         "stdlib/stdlib"-.-C.a; "stdlib/std_exit.cmx";
         "stdlib/std_exit"-.-C.o; "stdlib/libasmrun"-.-C.a;
         "stdlib/camlheader"; "stdlib/camlheader_ur"]
  begin fun env build ->
    let (_ : Command.t) =
      Ocamlbuild_pack.Ocaml_compiler.native_library_link_mllib
        "stdlib/stdlib.mllib" "stdlib/stdlib.cmxa" env build
    in
    import_stdlib_contents build ["cmi"];
    touch "native_stdlib_partial_mode"
  end;;

rule "C files"
  ~prod:("%"-.-C.o)
  ~dep:"%.c"
  ~insert:(`before "ocaml C stubs: c -> o")
  begin fun env _ ->
    let c = env "%.c" in
    mkobj (env "%") c (T(tags_of_pathname c++"c"++"compile"++ccomptype))
  end;;

rule "C files for windows dynamic libraries"
  ~prod:("%.d"-.-C.o)
  ~dep:"%.c"
  ~insert:(`before "C files")
  begin fun env _ ->
    let c = env "%.c" in
    mkdynobj (env "%") c (T(tags_of_pathname c++"c"++"compile"++"dll"++ccomptype))
  end;;

(* ../ is because .h files are not dependencies so they are not imported in build dir *)
flag ["c"; "compile"; "otherlibs_bigarray"] (S[A"-I"; P"../otherlibs/bigarray"]);;
flag [(* "ocaml" or "c"; *) "ocamlmklib"; "otherlibs_graph"] (S[Sh C.x11_link]);;
flag ["c"; "compile"; "otherlibs_graph"] (S[Sh C.x11_includes; A"-I../otherlibs/graph"]);;
flag ["c"; "compile"; "otherlibs_win32graph"] (A"-I../otherlibs/win32graph");;
flag ["c"; "compile"; "otherlibs_dbm"] (Sh C.dbm_includes);;
flag [(* "ocaml" oc "c"; *) "ocamlmklib"; "otherlibs_dbm"] (S[A"-oc"; A"otherlibs/dbm/mldbm"; Sh C.dbm_link]);;
flag ["ocaml"; "ocamlmklib"; "otherlibs_threads"] (S[A"-oc"; A"otherlibs/threads/vmthreads"]);;
flag ["c"; "compile"; "otherlibs_num"] begin
  S[A("-DBNG_ARCH_"^C.bng_arch);
    A("-DBNG_ASM_LEVEL="^C.bng_asm_level);
    A"-I"; P"../otherlibs/num"]
end;;
flag ["c"; "compile"; "otherlibs_win32unix"] (A"-I../otherlibs/win32unix");;
flag [(* "ocaml" or "c"; *) "ocamlmklib"; "otherlibs_win32unix"] (S[A"-cclib"; Quote (syslib "wsock32")]);;
flag ["c"; "link"; "dll"; "otherlibs_win32unix"] (syslib "wsock32");;
let flags = S[syslib "kernel32"; syslib "gdi32"; syslib "user32"] in
flag ["c"; "ocamlmklib"; "otherlibs_win32graph"] (S[A"-cclib"; Quote flags]);
flag ["c"; "link"; "dll"; "otherlibs_win32graph"] flags;;

if windows then flag ["c"; "compile"; "otherlibs_bigarray"] (A"-DIN_OCAML_BIGARRAY");;

if windows then flag ["ocamlmklib"] (A"-custom");;

flag ["ocaml"; "pp"; "ocamldoc_sources"] begin
  if windows then
    S[A"grep"; A"-v"; A"DEBUG"]
  else
    A"../ocamldoc/remove_DEBUG"
end;;

let ocamldoc = P"./ocamldoc/ocamldoc.opt" in
let stdlib_mlis =
  List.fold_right
    (fun x acc -> "stdlib"/(String.uncapitalize x)-.-"mli" :: acc)
    (string_list_of_file "stdlib/stdlib.mllib")
    ["otherlibs/unix/unix.mli"; "otherlibs/str/str.mli";
     "otherlibs/bigarray/bigarray.mli"; "otherlibs/num/num.mli"] in
rule "Standard library manual"
  ~prod:"ocamldoc/stdlib_man/Pervasives.3o"
  ~deps:stdlib_mlis
  begin fun _ _ ->
    Seq[Cmd(S[A"mkdir"; A"-p"; P"ocamldoc/stdlib_man"]);
        Cmd(S[ocamldoc; A"-man"; A"-d"; P"ocamldoc/stdlib_man";
              A"-I"; P "stdlib"; A"-I"; P"otherlibs/unix"; A"-I"; P"otherlibs/num";
              A"-t"; A"Ocaml library"; A"-man-mini"; atomize stdlib_mlis])]
  end;;

flag ["ocaml"; "compile"; "bootstrap_thread"]
     (S[A"-I"; P systhreads_dir; A"-I"; P threads_dir]);;

flag ["ocaml"; "link"; "bootstrap_thread"]
     (S[A"-I"; P systhreads_dir; A"-I"; P threads_dir]);;

flag ["ocaml"; "compile"; "otherlibs_labltk"] (S[A"-I"; P unix_dir]);;

flag ["c"; "compile"; "otherlibs_labltk"] (S[A"-Ibyterun"; Sh C.tk_defs; Sh C.sharedcccompopts]);;

(* Sys threads *)

rule "posix native systhreads"
  ~prod:"otherlibs/systhreads/posix_n.o"
  ~dep:"otherlibs/systhreads/posix.c"
  ~insert:`top
  begin fun _ _ ->
    Cmd(S[Sh C.nativecc; A"-O"; A"-I../asmrun"; A"-I../byterun";
          Sh C.nativecccompopts; Sh C.sharedcccompopts;
          A"-DNATIVE_CODE"; A("-DTARGET_"^C.arch); A("-DSYS_"^C.system); A"-c";
          A"otherlibs/systhreads/posix.c"; A"-o"; Px"otherlibs/systhreads/posix_n.o"])
  end;;

rule "posix bytecode systhreads"
  ~prod:"otherlibs/systhreads/posix_b.o"
  ~dep:"otherlibs/systhreads/posix.c"
  ~insert:`top
  begin fun _ _ ->
    Cmd(S[Sh C.bytecc; A"-O"; A"-I../byterun";
          Sh C.bytecccompopts; Sh C.sharedcccompopts;
          A"-c"; A"otherlibs/systhreads/posix.c"; A"-o"; Px"otherlibs/systhreads/posix_b.o"])
  end;;

rule "windows native systhreads"
  ~prod:("otherlibs/systhreads/win32_n"-.-C.o)
  ~dep:"otherlibs/systhreads/win32.c"
  ~insert:`top
  begin fun _ _ ->
    mknatobj "otherlibs/systhreads/win32_n"
             "otherlibs/systhreads/win32.c"
             (S[A"-I../asmrun"; A"-I../byterun"; A"-DNATIVE_CODE"])
  end;;

rule "windows bytecode static systhreads"
  ~prod:("otherlibs/systhreads/win32_b"-.-C.o)
  ~dep:"otherlibs/systhreads/win32.c"
  ~insert:`top
  begin fun _ _ ->
    mkobj "otherlibs/systhreads/win32_b" "otherlibs/systhreads/win32.c"
          ((*A"-O"; why ? *) A"-I../byterun")
  end;;

rule "windows bytecode dynamic systhreads"
  ~prod:("otherlibs/systhreads/win32_b.d"-.-C.o)
  ~dep:"otherlibs/systhreads/win32.c"
  ~insert:`top
  begin fun _ _ ->
    mkdynobj "otherlibs/systhreads/win32_b" "otherlibs/systhreads/win32.c"
             ((*A"-O"; why ? *) A"-I../byterun")
  end;;

if windows then begin
  rule "windows libthreadsnat.a"
    ~prod:("otherlibs/systhreads/libthreadsnat"-.-C.a)
    ~dep:("otherlibs/systhreads/win32_n"-.-C.o)
    ~insert:`top
    begin fun _ _ ->
      mklib ("otherlibs/systhreads/libthreadsnat"-.-C.a) (P("otherlibs/systhreads/win32_n"-.-C.o)) N
    end
end else begin
(* Dynamic linking with -lpthread is risky on many platforms, so
   do not create a shared object for libthreadsnat. *)
rule "libthreadsnat.a"
  ~prod:"otherlibs/systhreads/libthreadsnat.a"
  ~dep:"otherlibs/systhreads/posix_n.o"
  ~insert:`top
  begin fun _ _ ->
    mklib "otherlibs/systhreads/libthreadsnat.a" (A"otherlibs/systhreads/posix_n.o") N
  end;

(* See remark above: force static linking of libthreadsnat.a *)
flag ["ocaml"; "link"; "library"; "otherlibs_systhreads"; "native"] begin
  S[A"-cclib"; syscamllib "threadsnat"; (* A"-cclib"; syscamllib "unix"; seems to be useless and can be dangerous during bootstrap *) Sh C.pthread_link]
end;
end;;

if windows then
copy_rule "systhreads/libthreads.clib is diffrent on windows"
  ~insert:`top
  ("otherlibs/systhreads/libthreadswin32"-.-C.a)
  ("otherlibs/systhreads/libthreads"-.-C.a);;

flag ["ocaml"; "ocamlmklib"; "otherlibs_systhreads"] (S[(* A"-cclib"; syscamllib "unix";; seems to be useless and can be dangerous during bootstrap *) Sh C.pthread_link]);;


flag ["c"; "compile"; "otherlibs"] begin
  S[A"-I"; P"../byterun";
    A"-I"; P(".."/unix_dir);
    Sh C.bytecccompopts;
    Sh C.sharedcccompopts]
end;;

flag ["c"; "compile"; "otherlibs"; "cc"] (A"-O");;
flag ["c"; "compile"; "otherlibs"; "mingw"] (A"-O");;

(* The numeric opcodes *)
rule "The numeric opcodes"
  ~prod:"bytecomp/opcodes.ml"
  ~dep:"byterun/instruct.h"
  ~insert:`top
	begin fun _ _ ->
	  Cmd(Sh "sed -n -e '/^enum/p' -e 's/,//g' -e '/^  /p' byterun/instruct.h | \
        awk -f ../tools/make-opcodes > bytecomp/opcodes.ml")
  end;;

rule "tools/opnames.ml"
  ~prod:"tools/opnames.ml"
  ~dep:"byterun/instruct.h"
  begin fun _ _ ->
    Cmd(Sh"unset LC_ALL || : ; \
  	unset LC_CTYPE || : ; \
  	unset LC_COLLATE LANG || : ; \
  	sed -e '/\\/\\*/d' \
              -e '/^#/d' \
              -e 's/enum \\(.*\\) {/let names_of_\\1 = [|/' \
              -e 's/};$/ |]/' \
              -e 's/\\([A-Z][A-Z_0-9a-z]*\\)/\"\\1\"/g' \
              -e 's/,/;/g' \
          byterun/instruct.h > tools/opnames.ml")
  end;;

(* The version number *)
rule "stdlib/sys.ml"
  ~prod:"stdlib/sys.ml"
  ~deps:["stdlib/sys.mlp"; "VERSION"]
  begin fun _ _ ->
    let version = with_input_file "VERSION" input_line in
    Seq [rm_f "stdlib/sys.ml";
         Cmd (S[A"sed"; A"-e";
                A(sprintf "s,%%%%VERSION%%%%,%s," version);
                Sh"<"; P"stdlib/sys.mlp"; Sh">"; Px"stdlib/sys.ml"]);
         chmod (A"-w") "stdlib/sys.ml"]
  end;;

(* The predefined exceptions and primitives *)

rule "camlheader"
  ~prods:["stdlib/camlheader"; "stdlib/camlheader_ur"]
  ~deps:["stdlib/header.c"; "stdlib/headernt.c"]
  begin fun _ _ ->
    if C.sharpbangscripts then
      Cmd(Sh("echo '#!"^C.bindir^"/ocamlrun' > stdlib/camlheader && \
              echo '#!' | tr -d '\\012' > stdlib/camlheader_ur"))
    else if windows then
      Seq[mkexe "tmpheader.exe" (P"stdlib/headernt.c") (S[A"-I../byterun"; Sh C.extralibs]);
          rm_f "camlheader.exe";
          mv "tmpheader.exe" "stdlib/camlheader";
          cp "stdlib/camlheader" "stdlib/camlheader_ur"]
    else
      let tmpheader = "tmpheader"^C.exe in
      Cmd(S[Sh C.bytecc; Sh C.bytecccompopts; Sh C.bytecclinkopts;
            A"-I"; A"../stdlib";
            A("-DRUNTIME_NAME='\""^C.bindir^"/ocamlrun\"'");
            A"stdlib/header.c"; A"-o"; Px tmpheader; Sh"&&";
            A"strip"; P tmpheader; Sh"&&";
            A"mv"; P tmpheader; A"stdlib/camlheader"; Sh"&&";
            A"cp"; A"stdlib/camlheader"; A"stdlib/camlheader_ur"])
  end;;

rule "ocaml C stubs on windows: dlib & d.o* -> dll"
  ~prod:"%.dll"
  ~deps:["%.dlib"(*; "byterun/ocamlrun"-.-C.a*)]
  ~insert:`top
  begin fun env build ->
    let dlib = env "%.dlib" in
    let dll = env "%.dll" in
    let objs = string_list_of_file dlib in
    let include_dirs = Pathname.include_dirs_of (Pathname.dirname dll) in
    let resluts = build begin
      List.map begin fun d_o ->
        List.map (fun dir -> dir / (Pathname.update_extension C.o d_o)) include_dirs
      end objs
    end in
    let objs = List.map begin function
      | Outcome.Good d_o -> d_o
      | Outcome.Bad exn -> raise exn
    end resluts in
    mkdll dll (P("tmp"-.-C.a)) (S[atomize objs; P("byterun/ocamlrun"-.-C.a)])
          (T(tags_of_pathname dll++"dll"++"link"++"c"))
  end;;

copy_rule "win32unix use some unix files" "otherlibs/unix/%" "otherlibs/win32unix/%";;

(* Temporary rule *)
rule "tools/ocamlmklib.ml"
  ~prod:"tools/ocamlmklib.ml"
  ~dep:"tools/ocamlmklib.mlp"
  (fun _ _ -> cp "tools/ocamlmklib.mlp" "tools/ocamlmklib.ml");;


rule "bytecomp/runtimedef.ml"
  ~prod:"bytecomp/runtimedef.ml"
  ~deps:["byterun/primitives"; "byterun/fail.h"]
  begin fun _ _ ->
    Cmd(S[A"../build/mkruntimedef.sh";Sh">"; Px"bytecomp/runtimedef.ml"])
  end;;

(* Choose the right machine-dependent files *)

let mk_arch_rule ~src ~dst =
  let prod = "asmcomp"/dst in
  let dep = "asmcomp"/C.arch/src in
  rule (sprintf "arch specific files %S%%" dst) ~prod ~dep begin
    if windows then fun env _ -> cp (env dep) (env prod)
    else fun env _ -> ln_s (env (C.arch/src)) (env prod)
  end;;

mk_arch_rule ~src:(if ccomptype = "msvc" then "proc_nt.ml" else "proc.ml") ~dst:"proc.ml";;
List.iter (fun x -> mk_arch_rule ~src:x ~dst:x)
          ["arch.ml"; "reload.ml"; "scheduling.ml"; "selection.ml"];;

let emit_mlp = "asmcomp"/C.arch/(if ccomptype = "msvc" then "emit_nt.mlp" else "emit.mlp") in
rule "emit.mlp"
  ~prod:"asmcomp/emit.ml"
  ~deps:[emit_mlp; "tools/cvt_emit.byte"]
  begin fun _ _ ->
    Cmd(S[ocamlrun; P"tools/cvt_emit.byte"; Sh "<"; P emit_mlp;
          Sh">"; Px"asmcomp/emit.ml"])
  end;;

let p4  = Pathname.concat "camlp4"
let pa  = Pathname.concat (p4 "Camlp4Parsers")
let pr  = Pathname.concat (p4 "Camlp4Printers")
let fi  = Pathname.concat (p4 "Camlp4Filters")
let top = Pathname.concat (p4 "Camlp4Top")

let pa_r  = pa "Camlp4OCamlRevisedParser"
let pa_o  = pa "Camlp4OCamlParser"
let pa_q  = pa "Camlp4QuotationExpander"
let pa_qc = pa "Camlp4QuotationCommon"
let pa_rq = pa "Camlp4OCamlRevisedQuotationExpander"
let pa_oq = pa "Camlp4OCamlOriginalQuotationExpander"
let pa_rp = pa "Camlp4OCamlRevisedParserParser"
let pa_op = pa "Camlp4OCamlParserParser"
let pa_g  = pa "Camlp4GrammarParser"
let pa_l  = pa "Camlp4ListComprehension"
let pa_macro = pa "Camlp4MacroParser"
let pa_debug = pa "Camlp4DebugParser"

let pr_dump  = pr "Camlp4OCamlAstDumper"
let pr_r = pr "Camlp4OCamlRevisedPrinter"
let pr_o = pr "Camlp4OCamlPrinter"
let pr_a = pr "Camlp4AutoPrinter"
let fi_exc = fi "Camlp4ExceptionTracer"
let fi_tracer = fi "Camlp4Tracer"
let fi_meta = fi "MetaGenerator"
let camlp4_bin = p4 "Camlp4Bin"
let top_rprint = top "Rprint"
let top_top = top "Top"
let camlp4Profiler = p4 "Camlp4Profiler"

let camlp4lib_cma = p4 "camlp4lib.cma"
let camlp4lib_cmxa = p4 "camlp4lib.cmxa"

let special_modules =
  if Sys.file_exists "./boot/Profiler.cmo" then [camlp4Profiler] else []
;;

file_rule "camlp4/Camlp4_import.ml"
  ~deps:
    ["parsing/linenum.ml";
     "utils/misc.ml";
     "utils/terminfo.ml";
     "utils/warnings.ml";
     "parsing/location.ml";
     "parsing/asttypes.mli";
     "parsing/parsetree.mli";
     "myocamlbuild_config.ml";
     "utils/config.mlbuild";
     "parsing/longident.ml"]
  ~prod:"camlp4/Camlp4_import.ml"
  ~cache:(fun _ _ -> "0.1")
  begin fun _ oc ->
    Printf.fprintf oc "\
      module Misc = struct\n%a\nend;;\n\
      module Terminfo = struct\n%a\nend;;\n\
      module Linenum = struct\n%a\nend;;\n\
      module Warnings = struct\n%a\nend;;\n\
      module Location = struct\n%a\nend;;\n\
      module Longident = struct\n%a\nend;;\n\
      module Asttypes = struct\n%a\nend;;\n\
      module Parsetree = struct\n%a\nend;;\n\
      module Myocamlbuild_config = struct\n%a\nend;;\n\
      module Config = struct\n%a\nend;;\n%!"
      fp_cat "utils/misc.ml"
      fp_cat "utils/terminfo.ml"
      fp_cat "parsing/linenum.ml"
      fp_cat "utils/warnings.ml"
      fp_cat "parsing/location.ml"
      fp_cat "parsing/longident.ml"
      fp_cat "parsing/asttypes.mli"
      fp_cat "parsing/parsetree.mli"
      fp_cat "myocamlbuild_config.ml"
      fp_cat "utils/config.ml"
  end;;

let mk_camlp4_top_lib name modules =
  let name = "camlp4"/name in
  let cma = name-.-"cma" in
  let deps = special_modules @ modules @ [top_top] in
  let cmos = add_extensions ["cmo"] deps in
  rule cma
    ~deps:(camlp4lib_cma::cmos)
    ~prods:[cma]
    ~insert:(`before "ocaml: mllib & cmo* -> cma")
    begin fun _ _ ->
      Cmd(S[ocamlc; A"-a"; T(tags_of_pathname cma++"ocaml"++"link"++"byte");
            P camlp4lib_cma; A"-linkall"; atomize cmos; A"-o"; Px cma])
    end;;

let mk_camlp4_bin name ?unix:(link_unix=true) modules =
  let name = "camlp4"/name in
  let byte = name-.-"byte" in
  let native = name-.-"native" in
  let unix_cma, unix_cmxa, include_unix =
    if link_unix then A"unix.cma", A"unix.cmxa", S[A"-I"; P unix_dir] else N,N,N in
  let deps = special_modules @ modules @ [camlp4_bin] in
  let cmos = add_extensions ["cmo"] deps in
  let cmxs = add_extensions ["cmx"] deps in
  rule byte
    ~deps:(camlp4lib_cma::cmos)
    ~prod:(add_exe byte)
    ~insert:(`before "ocaml: cmo* -> byte")
    begin fun _ _ ->
      Cmd(S[ocamlc; include_unix; unix_cma; T(tags_of_pathname byte++"ocaml"++"link"++"byte");
            P camlp4lib_cma; A"-linkall"; atomize cmos; A"-o"; Px (add_exe byte)])
    end;
  rule native
    ~deps:(camlp4lib_cmxa::cmxs)
    ~prod:(add_exe native)
    ~insert:(`before "ocaml: cmx* & o* -> native")
    begin fun _ _ ->
      Cmd(S[ocamlopt; include_unix; unix_cmxa; T(tags_of_pathname native++"ocaml"++"link"++"native");
            P camlp4lib_cmxa; A"-linkall"; atomize cmxs; A"-o"; Px (add_exe native)])
    end;;

let mk_camlp4 name ?unix modules bin_mods top_mods =
  mk_camlp4_bin name ?unix (modules @ bin_mods);
  mk_camlp4_top_lib name (modules @ top_mods);;

copy_rule "camlp4: boot/Camlp4Ast.ml -> Camlp4/Struct/Camlp4Ast.ml"
  ~insert:`top "camlp4/boot/Camlp4Ast.ml" "camlp4/Camlp4/Struct/Camlp4Ast.ml";;

rule "camlp4: Camlp4/Struct/Lexer.ml -> boot/Lexer.ml"
  ~prod:"camlp4/boot/Lexer.ml"
  ~dep:"camlp4/Camlp4/Struct/Lexer.ml"
  begin fun _ _ ->
    Cmd(S[P"camlp4o"; P"camlp4/Camlp4/Struct/Lexer.ml";
          A"-printer"; A"r"; A"-o"; Px"camlp4/boot/Lexer.ml"])
  end;;

module Camlp4deps = struct
  let lexer = Genlex.make_lexer ["INCLUDE"; ";"; "="; ":"];;

  let rec parse strm =
    match Stream.peek strm with
    | None -> []
    | Some(Genlex.Kwd "INCLUDE") ->
        Stream.junk strm;
        begin match Stream.peek strm with
        | Some(Genlex.String s) ->
            Stream.junk strm;
            s :: parse strm
        | _ -> invalid_arg "Camlp4deps parse failure"
        end
    | Some _ ->
        Stream.junk strm;
        parse strm

  let parse_file file =
    with_input_file file begin fun ic ->
      let strm = Stream.of_channel ic in
      parse (lexer strm)
    end

  let build_deps build file =
    let includes = parse_file file in
    List.iter Outcome.ignore_good (build (List.map (fun i -> [i]) includes));
end;;

rule "camlp4: ml4 -> ml"
  ~prod:"%.ml"
  ~dep:"%.ml4"
  begin fun env build ->
    let ml4 = env "%.ml4" and ml = env "%.ml" in
    Camlp4deps.build_deps build ml4;
    Cmd(S[P cold_camlp4boot; A"-impl"; P ml4; A"-printer"; A"o";
          A"-D"; A"OPT"; A"-o"; Px ml])
  end;;

rule "camlp4: mlast -> ml"
  ~prod:"%.ml"
  ~deps:["%.mlast"; "camlp4/Camlp4/Camlp4Ast.partial.ml"]
  begin fun env _ ->
    let mlast = env "%.mlast" and ml = env "%.ml" in
    (* Camlp4deps.build_deps build mlast; too hard to lex *)
    Cmd(S[P cold_camlp4boot;
          A"-printer"; A"r";
          A"-filter"; A"map";
          A"-filter"; A"fold";
          A"-filter"; A"meta";
          A"-filter"; A"trash";
          A"-impl"; P mlast;
          A"-o"; Px ml])
  end;;

dep ["ocaml"; "compile"; "file:camlp4/Camlp4/Sig.ml"]
    ["camlp4/Camlp4/Camlp4Ast.partial.ml"];;

mk_camlp4_bin "camlp4" [];;
mk_camlp4 "camlp4boot" ~unix:false
  [pa_r; pa_qc; pa_q; pa_rp; pa_g; pa_macro; pa_debug; pa_l] [pr_dump] [top_rprint];;
mk_camlp4 "camlp4r"
  [pa_r; pa_rp] [pr_a] [top_rprint];;
mk_camlp4 "camlp4rf"
  [pa_r; pa_qc; pa_q; pa_rp; pa_g; pa_macro; pa_l] [pr_a] [top_rprint];;
mk_camlp4 "camlp4o"
  [pa_r; pa_o; pa_rp; pa_op] [pr_a] [];;
mk_camlp4 "camlp4of"
  [pa_r; pa_qc; pa_q; pa_o; pa_rp; pa_op; pa_g; pa_macro; pa_l] [pr_a] [];;
mk_camlp4 "camlp4oof"
  [pa_r; pa_o; pa_rp; pa_op; pa_qc; pa_oq; pa_g; pa_macro; pa_l] [pr_a] [];;
mk_camlp4 "camlp4orf"
  [pa_r; pa_o; pa_rp; pa_op; pa_qc; pa_rq; pa_g; pa_macro; pa_l] [pr_a] [];;


(* Labltk *)

Pathname.define_context "otherlibs/labltk/support" ["otherlibs/labltk/support"; "stdlib"];;
Pathname.define_context "otherlibs/labltk/compiler" ["otherlibs/labltk/compiler"; "otherlibs/labltk/support"; "stdlib"];;
Pathname.define_context "otherlibs/labltk/labltk" ["otherlibs/labltk/labltk"; "otherlibs/labltk/support"; "stdlib"];;
Pathname.define_context "otherlibs/labltk/camltk" ["otherlibs/labltk/camltk"; "otherlibs/labltk/support"; "stdlib"];;
Pathname.define_context "otherlibs/labltk/lib"
  ["otherlibs/labltk/labltk"; "otherlibs/labltk/camltk"; "otherlibs/labltk/support"; "stdlib"];;
Pathname.define_context "otherlibs/labltk/jpf"
  ["otherlibs/labltk/jpf"; "otherlibs/labltk/labltk"; "otherlibs/labltk/support"; "stdlib"];;
Pathname.define_context "otherlibs/labltk/frx"
  ["otherlibs/labltk/frx"; "otherlibs/labltk/camltk"; "otherlibs/labltk/support"; "stdlib"];;
Pathname.define_context "otherlibs/labltk/tkanim"
  ["otherlibs/labltk/tkanim"; "otherlibs/labltk/camltk"; "otherlibs/labltk/support"; "stdlib"];;
Pathname.define_context "otherlibs/labltk/browser"
  ["otherlibs/labltk/browser"; "otherlibs/labltk/labltk"; "otherlibs/labltk/support"; "parsing"; "utils"; "typing"; "stdlib"];;

file_rule "otherlibs/labltk/compiler/copyright"
  ~dep:"otherlibs/labltk/compiler/copyright"
  ~prod:"otherlibs/labltk/compiler/copyright.ml"
  ~cache:(fun _ _ -> "0.1")
  begin fun _ oc ->
    Printf.fprintf oc "let copyright = \"%a\";;\n\
                       let write ~w = w copyright;;"
      fp_cat "otherlibs/labltk/compiler/copyright"
  end;;

copy_rule "labltk tkcompiler" "otherlibs/labltk/compiler/maincompile.byte" "otherlibs/labltk/compiler/tkcompiler";;
copy_rule "labltk pp" "otherlibs/labltk/compiler/pp.byte" "otherlibs/labltk/compiler/pp";;
copy_rule "labltk ocamlbrowser" "otherlibs/labltk/browser/main.byte" "otherlibs/labltk/browser/ocamlbrowser";;

let builtins =
  let dir = "otherlibs/labltk/builtin" in
  List.filter (fun f -> not (Pathname.is_directory f))
    (List.map (fun f -> dir/f) (Array.to_list (Pathname.readdir dir)));;

let labltk_support =
  ["support"; "rawwidget"; "widget"; "protocol"; "textvariable"; "timer"; "fileevent"; "camltkwrap"];;

let labltk_generated_modules = 
  ["place"; "wm"; "imagephoto"; "canvas"; "button"; "text"; "label"; "scrollbar";
   "image"; "encoding"; "pixmap"; "palette"; "font"; "message"; "menu"; "entry";
   "listbox"; "focus"; "menubutton"; "pack"; "option"; "toplevel"; "frame";
   "dialog"; "imagebitmap"; "clipboard"; "radiobutton"; "tkwait"; "grab";
   "selection"; "scale"; "optionmenu"; "winfo"; "grid"; "checkbutton"; "bell"; "tkvars"];;

let labltk_generated_files =
  let dir = "otherlibs/labltk/labltk" in
  List.fold_right (fun x acc -> dir/x-.-"ml" :: dir/x-.-"mli" :: acc)
                   labltk_generated_modules [] in

rule "labltk/_tkgen.ml"
  ~deps:(["otherlibs/labltk/Widgets.src"; "otherlibs/labltk/compiler/tkcompiler"] @ builtins)
  ~prods:("otherlibs/labltk/labltk/_tkgen.ml" :: "otherlibs/labltk/labltk/labltk.ml" :: labltk_generated_files)
  begin fun env _ ->
    Cmd(S[A"cd"; A"otherlibs/labltk"; Sh"&&"; full_ocamlrun;
          A"compiler/tkcompiler"; A"-outdir"; Px"labltk"])
  end;;

let camltk_generated_modules =
  ["cPlace"; "cResource"; "cWm"; "cImagephoto"; "cCanvas"; "cButton"; "cText"; "cLabel";
   "cScrollbar"; "cImage"; "cEncoding"; "cPixmap"; "cPalette"; "cFont"; "cMessage";
   "cMenu"; "cEntry"; "cListbox"; "cFocus"; "cMenubutton"; "cPack"; "cOption"; "cToplevel";
   "cFrame"; "cDialog"; "cImagebitmap"; "cClipboard"; "cRadiobutton"; "cTkwait"; "cGrab";
   "cSelection"; "cScale"; "cOptionmenu"; "cWinfo"; "cGrid"; "cCheckbutton"; "cBell"; "cTkvars"];;

let camltk_generated_files =
  let dir = "otherlibs/labltk/camltk" in
  List.fold_right (fun x acc -> dir/x-.-"ml" :: dir/x-.-"mli" :: acc)
                  camltk_generated_modules [] in

rule "camltk/_tkgen.ml"
  ~deps:(["otherlibs/labltk/Widgets.src"; "otherlibs/labltk/compiler/tkcompiler"] @ builtins)
  ~prods:("otherlibs/labltk/camltk/_tkgen.ml" :: "otherlibs/labltk/camltk/camltk.ml" :: camltk_generated_files)
  begin fun env _ ->
    Cmd(S[A"cd"; A"otherlibs/labltk"; Sh"&&"; full_ocamlrun;
          A"compiler/tkcompiler"; A"-camltk"; A"-outdir"; Px"camltk"])
  end;;

rule "tk.ml"
  ~prod:"otherlibs/labltk/labltk/tk.ml"
  ~deps:(["otherlibs/labltk/labltk/_tkgen.ml";
          "otherlibs/labltk/compiler/pp.byte"]
         @ builtins)
  begin fun _ _ ->
    Seq[Cmd(Sh"\
            (echo 'open StdLabels'; \
             echo 'open Widget'; \
             echo 'open Protocol'; \
             echo 'open Support'; \
             echo 'open Textvariable'; \
             cat otherlibs/labltk/builtin/report.ml; \
             cat otherlibs/labltk/builtin/builtin_*.ml; \
             cat otherlibs/labltk/labltk/_tkgen.ml; \
             echo ; \
             echo ; \
             echo 'module Tkintf = struct'; \
             cat otherlibs/labltk/builtin/builtini_*.ml; \
             cat otherlibs/labltk/labltk/_tkigen.ml; \
             echo 'end (* module Tkintf *)'; \
             echo ; \
             echo ; \
             echo 'open Tkintf' ;\
             echo ; \
             echo ; \
             cat otherlibs/labltk/builtin/builtinf_*.ml; \
             cat otherlibs/labltk/labltk/_tkfgen.ml; \
             echo ; \
            ) > otherlibs/labltk/labltk/_tk.ml");
        Cmd(S[ocamlrun; P"otherlibs/labltk/compiler/pp.byte"; Sh"<"; P"otherlibs/labltk/labltk/_tk.ml";
              Sh">"; Px"otherlibs/labltk/labltk/tk.ml"]);
        rm_f "otherlibs/labltk/labltk/_tk.ml"]
  end;;

rule "cTk.ml"
  ~prod:"otherlibs/labltk/camltk/cTk.ml"
  ~deps:(["otherlibs/labltk/camltk/_tkgen.ml";
          "otherlibs/labltk/compiler/pp.byte"]
         @ builtins)
  begin fun _ _ ->
    Seq[Cmd(Sh"\
        (echo '##define CAMLTK'; \
         echo 'include Camltkwrap'; \
         echo 'open Widget'; \
         echo 'open Protocol'; \
         echo 'open Textvariable'; \
         echo ; \
         cat otherlibs/labltk/builtin/report.ml; \
         echo ; \
         cat otherlibs/labltk/builtin/builtin_*.ml; \
         echo ; \
         cat otherlibs/labltk/camltk/_tkgen.ml; \
         echo ; \
         echo ; \
         echo 'module Tkintf = struct'; \
         cat otherlibs/labltk/builtin/builtini_*.ml; \
         cat otherlibs/labltk/camltk/_tkigen.ml; \
         echo 'end (* module Tkintf *)'; \
         echo ; \
         echo ; \
         echo 'open Tkintf' ;\
         echo ; \
         echo ; \
         cat otherlibs/labltk/builtin/builtinf_*.ml; \
         cat otherlibs/labltk/camltk/_tkfgen.ml; \
         echo ; \
        ) > otherlibs/labltk/camltk/_cTk.ml");
        Cmd(S[ocamlrun; P"otherlibs/labltk/compiler/pp.byte"; Sh"<"; P"otherlibs/labltk/camltk/_cTk.ml";
              Sh">"; Px"otherlibs/labltk/camltk/cTk.ml"]);
        rm_f "otherlibs/labltk/camltk/_cTk.ml"]
  end;;

let labltk_lib_contents =
    labltk_support
 @  "tk"
 :: labltk_generated_modules
 @  "cTk"
 :: camltk_generated_modules;;

let labltk_contents obj_ext =
    List.map (fun x -> "otherlibs/labltk/support"/x-.-obj_ext) labltk_support
 @  "otherlibs/labltk/labltk/tk"-.-obj_ext
 :: List.map (fun x -> "otherlibs/labltk/labltk"/x-.-obj_ext) labltk_generated_modules
 @  "otherlibs/labltk/camltk/cTk"-.-obj_ext
 :: List.map (fun x -> "otherlibs/labltk/camltk"/x-.-obj_ext) camltk_generated_modules;;

let labltk_cma_contents = labltk_contents "cmo" in
rule "labltk.cma"
  ~prod:"otherlibs/labltk/lib/labltk.cma"
  ~deps:labltk_cma_contents
  (Ocamlbuild_pack.Ocaml_compiler.byte_library_link_modules
      labltk_lib_contents "otherlibs/labltk/lib/labltk.cma");;

let labltk_cmxa_contents = labltk_contents "cmx" in
rule "labltk.cmxa"
  ~prod:"otherlibs/labltk/lib/labltk.cmxa"
  ~deps:labltk_cmxa_contents
  (Ocamlbuild_pack.Ocaml_compiler.native_library_link_modules
      labltk_lib_contents "otherlibs/labltk/lib/labltk.cmxa");;

rule "labltktop"
  ~prod:(add_exe "otherlibs/labltk/lib/labltktop")
  ~deps:["toplevel/toplevellib.cma"; "toplevel/topstart.cmo";
         "otherlibs/labltk/lib/labltk.cma"; "otherlibs/labltk/support/liblabltk"-.-C.a]
  begin fun _ _ ->
    Cmd(S[!Options.ocamlc; A"-verbose"; A"-linkall"; A"-o"; Px(add_exe "otherlibs/labltk/lib/labltktop");
          A"-I"; P"otherlibs/labltk/support"; A"-I"; P"toplevel"; P"toplevellib.cma";
          A"-I"; P"otherlibs/labltk/labltk"; A"-I"; P"otherlibs/labltk/camltk";
          A"-I"; P"otherlibs/labltk/lib"; P"labltk.cma"; A"-I"; P unix_dir; P"unix.cma";
          A"-I"; P"otherlibs/str"; A"-I"; P "stdlib"; P"str.cma"; P"topstart.cmo"])
  end;;

let labltk_installdir = C.libdir/"labltk" in
file_rule "labltk"
  ~prod:"otherlibs/labltk/lib/labltk"
  ~cache:(fun _ _ -> labltk_installdir)
  begin fun _ oc ->
    Printf.fprintf oc
      "#!/bin/sh\n\
       exec %s -I %s $*\n" (labltk_installdir/"labltktop") labltk_installdir
  end;;

use_lib "otherlibs/labltk/browser/main" "toplevel/toplevellib";;
use_lib "otherlibs/labltk/browser/main" "otherlibs/labltk/browser/jglib";;
use_lib "otherlibs/labltk/browser/main" "otherlibs/labltk/lib/labltk";;

if windows then begin

  dep ["ocaml"; "link"; "program"; "ocamlbrowser"] ["otherlibs/labltk/browser/winmain"-.-C.o];
  flag ["ocaml"; "link"; "program"; "ocamlbrowser"] (S[A"-custom"; A"threads.cma"]);

  match ccomptype with
  | "cc" -> flag ["ocaml"; "link"; "program"; "ocamlbrowser"] (S[A"-ccopt"; A"-Wl,--subsystem,windows"])
  | "msvc" -> flag ["ocaml"; "link"; "program"; "ocamlbrowser"] (S[A"-ccopt"; A"/link /subsystem:windows"])
  | _ -> assert false

end;;

let space_sep_strings s = Ocamlbuild_pack.Lexers.space_sep_strings (Lexing.from_string s);;

flag [(* "ocaml" or "c"; *) "ocamlmklib"; "otherlibs_labltk"]
  (if windows then begin
    S(List.fold_right (fun s acc -> A"-cclib" :: A s :: acc) (space_sep_strings C.tk_link) [])
   end else Sh C.tk_link);;

flag ["ocaml"; "link"; "program"; "otherlibs_labltk"] (S[A"-I"; A"otherlibs/labltk/support"]);;

flag ["c"; "compile"; "otherlibs_labltk"] (A"-Iotherlibs/labltk/support");;

copy_rule "ocamlbrowser dummy module"
  ("otherlibs/labltk/browser"/(if windows then "dummyWin.mli" else "dummyUnix.mli"))
  "otherlibs/labltk/browser/dummy.mli";;

      end in ()
  | _ -> ()
end
