(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(* Xavier Leroy and Jerome Vouillon, projet Cristal, INRIA Rocquencourt*)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(**** Typing of type definitions ****)

open Misc
open Parsetree
open Types
open Typedtree
open Typetexp

type error =
    Repeated_parameter
  | Duplicate_constructor of string
  | Too_many_constructors
  | Duplicate_label of string
  | Recursive_abbrev of string
  | Definition_mismatch of type_expr
  | Constraint_failed of type_expr * type_expr
  | Unconsistent_constraint
  | Type_clash of (type_expr * type_expr) list
  | Parameters_differ of type_expr * type_expr
  | Null_arity_external
  | Unbound_type_var
  | Unbound_exception of Longident.t
  | Not_an_exception of Longident.t

exception Error of Location.t * error

(* Enter all declared types in the environment as abstract types *)

let enter_type env (name, sdecl) id =
  let decl =
    { type_params =
        List.map (fun _ -> Btype.newgenvar ()) sdecl.ptype_params;
      type_arity = List.length sdecl.ptype_params;
      type_kind = Type_abstract;
      type_manifest = None }
  in
  Env.add_type id decl env

(* Determine if a type is (an abbreviation for) the type "float" *)

let is_float env ty =
  match Ctype.repr (Ctype.expand_head env ty) with
    {desc = Tconstr(p, _, _)} -> Path.same p Predef.path_float
  | _ -> false

(* Translate one type declaration *)

module StringSet =
  Set.Make(struct
    type t = string
    let compare = compare
  end)

let transl_declaration env (name, sdecl) id =
  (* Bind type parameters *)
  reset_type_variables();
  let params =
    try List.map (enter_type_variable true) sdecl.ptype_params
    with Already_bound ->
      raise(Error(sdecl.ptype_loc, Repeated_parameter))
  in
  let decl =
    { type_params = params;
      type_arity = List.length params;
      type_kind =
        begin match sdecl.ptype_kind with
          Ptype_abstract ->
            Type_abstract
        | Ptype_variant cstrs ->
            let all_constrs = ref StringSet.empty in
            List.iter
              (fun (name, args) ->
                if StringSet.mem name !all_constrs then
                  raise(Error(sdecl.ptype_loc, Duplicate_constructor name));
                all_constrs := StringSet.add name !all_constrs)
              cstrs;
            if List.length (List.filter (fun (name, args) -> args <> []) cstrs)
               > Config.max_tag then
              raise(Error(sdecl.ptype_loc, Too_many_constructors));
            Type_variant(List.map
              (fun (name, args) ->
                      (name, List.map (transl_simple_type env true) args))
              cstrs)
        | Ptype_record lbls ->
            let all_labels = ref StringSet.empty in
            List.iter
              (fun (name, mut, arg) ->
                if StringSet.mem name !all_labels then
                  raise(Error(sdecl.ptype_loc, Duplicate_label name));
                all_labels := StringSet.add name !all_labels)
              lbls;
            let lbls' =
              List.map
                (fun (name, mut, arg) ->
                         (name, mut, transl_simple_type env true arg))
                lbls in
            let rep =
              if List.for_all (fun (name, mut, arg) -> is_float env arg) lbls'
              then Record_float
              else Record_regular in
            Type_record(lbls', rep)
        end;
      type_manifest =
        begin match sdecl.ptype_manifest with
          None -> None
        | Some sty ->
            let ty = transl_simple_type env true sty in
            if Ctype.cyclic_abbrev env id ty then
              raise(Error(sdecl.ptype_loc, Recursive_abbrev name));
            Some ty
        end; } in

  (* Check constraints *)
  List.iter
    (function (sty, sty', loc) ->
       try
         Ctype.unify env (transl_simple_type env false sty)
                         (transl_simple_type env false sty')
       with Ctype.Unify _ ->
         raise(Error(loc, Unconsistent_constraint)))
    sdecl.ptype_cstrs;

  (id, decl)

(* Generalize a type declaration *)

let generalize_decl decl =
  List.iter Ctype.generalize decl.type_params;
  begin match decl.type_kind with
    Type_abstract ->
      ()
  | Type_variant v ->
      List.iter (fun (_, tyl) -> List.iter Ctype.generalize tyl) v
  | Type_record(r, rep) ->
      List.iter (fun (_, _, ty) -> Ctype.generalize ty) r
  end;
  begin match decl.type_manifest with
    None    -> ()
  | Some ty -> Ctype.generalize ty
  end

(* Check that all constraints are enforced *)

module TypeSet =
  Set.Make
    (struct
      type t = type_expr
      let compare t1 t2 = t1.id - t2.id
    end)

let rec check_constraints_rec env loc visited ty =
  let ty = Ctype.repr ty in
  if TypeSet.mem ty !visited then () else begin
  visited := TypeSet.add ty !visited;
  match ty.desc with
  | Tconstr (path, args, _) ->
      Ctype.begin_def ();
      let args' = List.map (fun _ -> Ctype.newvar ()) args in
      let ty' = Ctype.newconstr path args' in
      begin try Ctype.enforce_constraints env ty'
      with Ctype.Unify _ -> assert false
      end;
      Ctype.end_def ();
      Ctype.generalize ty';
      let targs = Btype.newgenty (Ttuple args)
      and targs' = Btype.newgenty (Ttuple args') in
      if not (Ctype.moregeneral env false targs' targs) then
        raise (Error(loc, Constraint_failed (ty, ty')));
      List.iter (check_constraints_rec env loc visited) args
  | _ ->
      Btype.iter_type_expr (check_constraints_rec env loc visited) ty
  end

let check_constraints env (_, sdecl) (_, decl) =
  let visited = ref TypeSet.empty in
  begin match decl.type_kind with
  | Type_abstract -> ()
  | Type_variant l ->
      let pl =
        match sdecl.ptype_kind with Ptype_variant pl -> pl | _ -> assert false
      in
      List.iter
        (fun (name, tyl) ->
          let styl = try List.assoc name pl with Not_found -> assert false in
          List.iter2
            (fun sty ty -> check_constraints_rec env sty.ptyp_loc visited ty)
            styl tyl)
        l
  | Type_record (l, _) ->
      let pl =
        match sdecl.ptype_kind with Ptype_record pl -> pl | _ -> assert false
      in
      let rec get_loc name = function
          [] -> assert false
        | (name', _, sty) :: tl ->
            if name = name' then sty.ptyp_loc else get_loc name tl
      in
      List.iter
        (fun (name, _, ty) ->
          check_constraints_rec env (get_loc name pl) visited ty)
        l
  end;
  begin match decl.type_manifest with
  | None -> ()
  | Some ty ->
      let sty =
        match sdecl.ptype_manifest with Some sty -> sty | _ -> assert false
      in
      check_constraints_rec env sty.ptyp_loc visited ty
  end

(*
   If both a variant/record definition and a type equation are given,
   need to check that the equation refers to a type of the same kind
   with the same constructors and labels.
*)
let check_abbrev env (_, sdecl) (id, decl) =
  match decl with
    {type_kind = (Type_variant _ | Type_record _); type_manifest = Some ty} ->
      begin match (Ctype.repr ty).desc with
        Tconstr(path, args, _) ->
          begin try
            let decl' = Env.find_type path env in
            if List.length args = List.length decl.type_params
            && Ctype.equal env false args decl.type_params
            && Includecore.type_declarations env id
                decl'
                (Subst.type_declaration (Subst.add_type id path Subst.identity)
                                        decl)
            then ()
            else raise(Error(sdecl.ptype_loc, Definition_mismatch ty))
          with Not_found ->
            raise(Error(sdecl.ptype_loc, Definition_mismatch ty))
          end
      | _ -> raise(Error(sdecl.ptype_loc, Definition_mismatch ty))
      end
  | _ -> ()

(* Check for ill-defined abbrevs *)

(* Occur check *)
let check_recursive_abbrev env (name, sdecl) (id, decl) =
  match decl.type_manifest with
    Some ty ->
      begin try Ctype.correct_abbrev env id decl.type_params ty with
        Ctype.Recursive_abbrev ->
          raise(Error(sdecl.ptype_loc, Recursive_abbrev name))
      end
  | _ ->
      ()

(* Recursive expansion check *)

let rec check_expansion_rec env id args loc id_loc_list visited ty =
  let ty = Ctype.repr ty in
  if List.memq ty visited then () else
  let visited = ty :: visited in
  begin match ty.desc with
  | Tconstr(Path.Pident id' as path, args', _) ->
      if Ident.same id id' then begin
        if not (Ctype.equal env false args args') then
          raise (Error(loc, Parameters_differ(ty, Ctype.newconstr path args)))
      end else begin try
        let loc = List.assoc id' id_loc_list
        and id_loc_list = List.remove_assoc id' id_loc_list in
        let (params, body) = Env.find_type_expansion path env in
        let (params, body) = Ctype.instance_parameterized_type params body in
        begin
          try List.iter2 (Ctype.unify env) params args'
          with Ctype.Unify _ -> assert false
        end;
        check_expansion_rec env id args loc id_loc_list visited body
      with Not_found -> ()
      end
  | _ -> ()
  end;
  Btype.iter_type_expr
    (check_expansion_rec env id args loc id_loc_list visited) ty

let check_expansion env id_loc_list (id, decl) =
  match decl.type_manifest with
  | None -> ()
  | Some body ->
      let (args, body) =
        Ctype.instance_parameterized_type decl.type_params body in
      check_expansion_rec env id args
        (List.assoc id id_loc_list) id_loc_list [] body

(* Translate a set of mutually recursive type declarations *)
let transl_type_decl env name_sdecl_list =
  (* Create identifiers. *)
  let id_list =
    List.map (fun (name, _) -> Ident.create name) name_sdecl_list
  in
  (*
     Since we've introduced fresh idents, make sure the definition
     level is at least the binding time of these events. Otherwise,
     passing one of the recursively-defined type constrs as argument
     to an abbreviation may fail.
  *)
  Ctype.init_def(Ident.current_time());
  Ctype.begin_def();
  (* Enter types. *)
  let temp_env = List.fold_left2 enter_type env name_sdecl_list id_list in
  (* Translate each declaration. *)
  let decls =
    List.map2 (transl_declaration temp_env) name_sdecl_list id_list in
  (* Generalize type declarations. *)
  Ctype.end_def();
  List.iter (function (_, decl) -> generalize_decl decl) decls;
  (* Build the final env. *)
  let newenv =
    List.fold_right
      (fun (id, decl) env -> Env.add_type id decl env)
      decls env
  in
  (* Check for recursive abbrevs *)
  List.iter2 (check_recursive_abbrev newenv) name_sdecl_list decls;
  (* Check that all type variable are closed *)
  List.iter2
    (fun (_, sdecl) (id, decl) ->
       match Ctype.closed_type_decl decl with
         Some _ -> raise(Error(sdecl.ptype_loc, Unbound_type_var))
       | None   -> ())
    name_sdecl_list decls;
  (* Check re-exportation *)
  List.iter2 (check_abbrev newenv) name_sdecl_list decls;
  (* Check that constraints are enforced *)
  List.iter2 (check_constraints newenv) name_sdecl_list decls;
  (* Check that abbreviations have same parameters *)
  let id_loc_list =
    List.map2
      (fun id (_,sdecl) ->
        match sdecl.ptype_manifest with None -> []
        | Some {ptyp_loc=loc} -> [id, loc])
      id_list name_sdecl_list
  in
  List.iter (check_expansion newenv (List.flatten id_loc_list)) decls;
  (* Done *)
  (decls, newenv)

(* Translate an exception declaration *)
let transl_exception env excdecl =
  reset_type_variables();
  Ctype.begin_def();
  let types = List.map (transl_simple_type env true) excdecl in
  Ctype.end_def();
  List.iter Ctype.generalize types;
  types

(* Translate an exception rebinding *)
let transl_exn_rebind env loc lid =
  let cdescr =
    try
      Env.lookup_constructor lid env
    with Not_found ->
      raise(Error(loc, Unbound_exception lid)) in
  match cdescr.cstr_tag with
    Cstr_exception path -> (path, cdescr.cstr_args)
  | _ -> raise(Error(loc, Not_an_exception lid))

(* Translate a value declaration *)
let transl_value_decl env valdecl =
  let ty = Typetexp.transl_type_scheme env valdecl.pval_type in
  match valdecl.pval_prim with
    [] ->
      { val_type = ty; val_kind = Val_reg }
  | decl ->
      let arity = Ctype.arity ty in
      if arity = 0 then
        raise(Error(valdecl.pval_type.ptyp_loc, Null_arity_external));
      let prim = Primitive.parse_declaration arity decl in
      { val_type = ty; val_kind = Val_prim prim }

(* Translate a "with" constraint -- much simplified version of
    transl_type_decl. *)
let transl_with_constraint env sdecl =
  reset_type_variables();
  Ctype.begin_def();
  let params =
    try
      List.map (enter_type_variable true) sdecl.ptype_params
    with Already_bound ->
      raise(Error(sdecl.ptype_loc, Repeated_parameter)) in
  List.iter
    (function (ty, ty', loc) ->
       try
         Ctype.unify env (transl_simple_type env false ty)
                         (transl_simple_type env false ty')
       with Ctype.Unify _ ->
         raise(Error(loc, Unconsistent_constraint)))
    sdecl.ptype_cstrs;
  let decl =
    { type_params = params;
      type_arity = List.length params;
      type_kind = Type_abstract;
      type_manifest =
        begin match sdecl.ptype_manifest with
          None -> None
        | Some sty -> Some(transl_simple_type env true sty)
        end }
  in
  Ctype.end_def();
  generalize_decl decl;
  decl

(**** Error report ****)

open Format

let report_error ppf = function
  | Repeated_parameter ->
      fprintf ppf "A type parameter occurs several times"
  | Duplicate_constructor s ->
      fprintf ppf "Two constructors are named %s" s
  | Too_many_constructors ->
      fprintf ppf "Too many non-constant constructors -- \
                   maximum is %i non-constant constructors"
        Config.max_tag
  | Duplicate_label s ->
      fprintf ppf "Two labels are named %s" s
  | Recursive_abbrev s ->
      fprintf ppf "The type abbreviation %s is cyclic" s
  | Definition_mismatch ty ->
      Printtyp.reset_and_mark_loops ty;
      fprintf ppf
        "The variant or record definition does not match that of type@ %a"
        Printtyp.type_expr ty
  | Constraint_failed (ty, ty') ->
      fprintf ppf "Constraints are not satisfied in this type.@.";
      Printtyp.reset_and_mark_loops ty;
      Printtyp.mark_loops ty';
      fprintf ppf "@[<hv>Type@ %a@ should be an instance of@ %a@]"
        Printtyp.type_expr ty Printtyp.type_expr ty'
  | Parameters_differ (ty, ty') ->
      Printtyp.reset_and_mark_loops ty;
      Printtyp.mark_loops ty';
      fprintf ppf
        "@[<hv>In this definition, type@ %a@ should be@ %a@]"
        Printtyp.type_expr ty Printtyp.type_expr ty'
  | Unconsistent_constraint ->
      fprintf ppf "The type constraints are not consistent"
  | Type_clash trace ->
      Printtyp.report_unification_error ppf trace
        (function ppf ->
           fprintf ppf "This type constructor expands to type")
        (function ppf ->
           fprintf ppf "but is here used with type")
  | Null_arity_external ->
      fprintf ppf "External identifiers must be functions"
  | Unbound_type_var ->
      fprintf ppf "A type variable is unbound in this type declaration"
  | Unbound_exception lid ->
      fprintf ppf "Unbound exception constructor@ %a" Printtyp.longident lid
  | Not_an_exception lid ->
      fprintf ppf "The constructor@ %a@ is not an exception"
        Printtyp.longident lid
