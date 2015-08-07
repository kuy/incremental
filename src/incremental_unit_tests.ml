open Core.Std
open Import
open Std

let does_raise = Exn.does_raise

let verbose = verbose

(* A little wrapper around [Incremental.Make] to add some utilities for testing. *)
module Make () = struct

  include Incremental.Make ()

  let value = Observer.value_exn

  let watch = Var.watch

  let disallow_future_use = Observer.disallow_future_use

  let advance_clock_by span = advance_clock ~to_:(Time.add (now ()) span)

  let invalid =
    let r = ref None in
    let x = Var.create 13 in
    let o = observe (bind (watch x) (fun i -> r := Some (const i); return ())) in
    stabilize ();
    let t = Option.value_exn !r in
    Var.set x 14;
    stabilize ();
    disallow_future_use o;
    t
  ;;

  let stabilize_ where =
    if verbose then Debug.am where;
    State.invariant State.t;
    stabilize ();
    State.invariant State.t;
    invariant ignore invalid;
  ;;

  module On_update_queue (Update : sig type 'a t with compare, sexp_of end) = struct
    let on_update_queue () =
      let r = ref [] in
      (fun e -> r := e :: !r),
      (fun expect ->
         <:test_result< int Update.t list >> (List.rev !r) ~expect;
         r := [])
  end

  let on_observer_update_queue =
    let module M = On_update_queue (Observer.Update) in
    M.on_update_queue
  ;;

  let on_update_queue =
    let module M = On_update_queue (Update) in
    M.on_update_queue
  ;;

  let save_dot_ =
    let r = ref 0 in
    fun () ->
      incr r;
      let dot_file = sprintf "/tmp/sweeks/z.dot.%d" !r in
      save_dot dot_file;
      let prog = "my-dot" in
      Unix.waitpid_exn (Unix.fork_exec ~prog ~args:[ prog; dot_file ] ());
  ;;

  let _ = save_dot_

  let _squelch_unused_module_warning_ = ()

end

TEST_MODULE = struct

  module I = Make ()

  open I

  include (struct

    type nonrec 'a t = 'a t
    type 'a incremental = 'a t

    module Infix = Infix

    module Before_or_after = Before_or_after

    let invariant = invariant

    let stabilize = stabilize

    let keep_node_creation_backtrace = keep_node_creation_backtrace

    let observe = observe  (* used in lots of tests *)

    let user_info = user_info

    let set_user_info = set_user_info

    let save_dot = save_dot

    module Update = Update

    module Packed = Packed

    let pack = pack

    module State = struct

      open State

      type nonrec t = t with sexp_of

      let invariant = invariant
      let t = t

      TEST_UNIT = invariant t

      let timing_wheel_length = timing_wheel_length

      let max_height_allowed = max_height_allowed

      TEST = max_height_allowed t = 128  (* the default *)

      let max_height_seen = max_height_seen

      TEST = max_height_seen t = 3 (* because of [let invalid] above *)

      let set_max_height_allowed = set_max_height_allowed

      TEST_UNIT =
        List.iter [ -1; 2 ] ~f:(fun height ->
          assert (does_raise (fun () -> set_max_height_allowed t height)));
      ;;

      TEST_UNIT = set_max_height_allowed t 10

      TEST = max_height_allowed t = 10

      TEST_UNIT = set_max_height_allowed t 128

      TEST_UNIT =
        set_max_height_allowed t 256;
        let rec loop n =
          if n = 0
          then return 0
          else loop (n - 1) >>| fun i -> i + 1
        in
        let o = observe (loop (max_height_allowed t)) in
        stabilize_ _here_;
        assert (Observer.value_exn o = max_height_allowed t);
      ;;

      TEST = max_height_allowed t = max_height_seen t

      TEST_UNIT = invariant t

      let num_active_observers = num_active_observers

      TEST_UNIT =
        Gc.full_major ();
        stabilize_ _here_;
        let n = num_active_observers t in
        let o = observe (const 0) in
        disallow_future_use o;
        <:test_result< int >> (num_active_observers t) ~expect:n;
      ;;

      TEST_UNIT =
        Gc.full_major ();
        stabilize_ _here_;
        let n = num_active_observers t in
        let o = observe (const 0) in
        stabilize_ _here_;
        <:test_result< int >> (num_active_observers t) ~expect:(n + 1);
        disallow_future_use o;
        <:test_result< int >> (num_active_observers t) ~expect:n;
        stabilize_ _here_;
        <:test_result< int >> (num_active_observers t) ~expect:n;
      ;;

      TEST_UNIT = (* [observe ~should_finalize:true] *)
        Gc.full_major ();
        stabilize_ _here_;
        let _o = observe (const 13) ~should_finalize:true in
        stabilize_ _here_;
        let n = num_active_observers t in
        Gc.full_major ();
        stabilize_ _here_;
        <:test_result< int >> (num_active_observers t) ~expect:(n - 1)
      ;;

      TEST_UNIT = (* [observe ~should_finalize:false] *)
        Gc.full_major ();
        stabilize_ _here_;
        let _o = observe (const 13) ~should_finalize:false in
        stabilize_ _here_;
        let n = num_active_observers t in
        Gc.full_major ();
        stabilize_ _here_;
        <:test_result< int >> (num_active_observers t) ~expect:n
      ;;

      let num_nodes_became_necessary                       = num_nodes_became_necessary
      let num_nodes_became_unnecessary                     = num_nodes_became_unnecessary
      let num_nodes_changed                                = num_nodes_changed
      let num_nodes_created                                = num_nodes_created
      let num_nodes_invalidated                            = num_nodes_invalidated
      let num_nodes_recomputed                             = num_nodes_recomputed
      let num_stabilizes                                   = num_stabilizes
      let num_var_sets                                     = num_var_sets

      let num_nodes_recomputed_directly_because_min_height =
        num_nodes_recomputed_directly_because_min_height
      ;;

      TEST_UNIT =
        let var = Var.create 1 in
        let o =
          observe
            (map2
               (map2 (Var.watch var) (const 1) ~f:(+))
               (map2 (const 2) (const 3) ~f:(+))
               ~f:(+))
        in
        stabilize_ _here_;
        let stat1 = num_nodes_recomputed_directly_because_min_height t in
        Var.set var 2;
        stabilize_ _here_;
        let stat2 = num_nodes_recomputed_directly_because_min_height t in
        <:test_eq< int >> (stat2 - stat1) 2;
        disallow_future_use o;
      ;;

      let num_nodes_recomputed_directly_because_one_child =
        num_nodes_recomputed_directly_because_one_child
      ;;

      TEST_UNIT =
        (* We can't use the same variable twice otherwise the optimization is not
           applied. *)
        let var1 = Var.create 1 in
        let var2 = Var.create 1 in
        let o var = observe (map (map (Var.watch var) ~f:Fn.id) ~f:Fn.id) in
        let o1 = o var1 in
        let o2 = o var2 in
        stabilize_ _here_;
        let stat1 = num_nodes_recomputed_directly_because_one_child t in
        Var.set var1 2;
        Var.set var2 2;
        stabilize_ _here_;
        let stat2 = num_nodes_recomputed_directly_because_one_child t in
        <:test_result< int >> (stat2 - stat1) ~expect:4;
        disallow_future_use o1;
        disallow_future_use o2;
      ;;

      module Stats = Stats
      let stats = stats
    end

    let sexp_of_t = sexp_of_t

    TEST_UNIT =
      State.( invariant t );
      let i = 13 in
      let t = const i in
      let o = observe t in
      stabilize_ _here_;
      <:test_eq< Sexp.t >>
        (t |> <:sexp_of< int t >>)
        (i |> <:sexp_of< int >>);
      disallow_future_use o;
    ;;

    let is_invalid t =
      let o = observe t in
      stabilize_ _here_;
      let result = is_error (Observer.value o) in
      disallow_future_use o;
      result
    ;;

    let is_invalidated_on_bind_rhs (f : int -> _ t) =
      let x = Var.create 13 in
      let r = ref None in
      let o1 = observe (Var.watch x >>= fun i -> r := Some (f i); return ()) in
      stabilize_ _here_;
      let t = Option.value_exn !r in
      let o2 = observe t in
      Var.set x 14;
      stabilize_ _here_;
      let result = is_invalid t in
      disallow_future_use o1;
      disallow_future_use o2;
      result
    ;;

    TEST = is_invalid invalid

    let is_valid = is_valid

    TEST = is_valid (const 3)
    TEST = not (is_valid invalid)

    let const        = const
    let return       = return
    let is_const     = is_const
    let is_necessary = is_necessary

    TEST_UNIT =
      List.iter [ const; return ] ~f:(fun const ->
        let i = const 13 in
        assert (is_const i);
        assert (not (is_necessary i));
        let o = observe i in
        assert (not (is_necessary i));
        stabilize_ _here_;
        assert (is_necessary i);
        assert (value o = 13);
        assert (is_const i));
    ;;

    TEST = is_invalidated_on_bind_rhs (fun _ -> const 13)

    module Var = struct

      open Var

      type nonrec 'a t = 'a t with sexp_of

      let create_ ?use_current_scope where value =
        if verbose then Debug.am where;
        create ?use_current_scope value
      ;;

      let create       = create
      let latest_value = latest_value
      let set          = set
      let value        = value
      let watch        = watch

      TEST_UNIT = (* observing a var after stabilization *)
        let x = create_ _here_ 0 in
        stabilize_ _here_;
        let o = observe (watch x) in
        stabilize_ _here_;
        assert (Observer.value_exn o = 0);
      ;;

      TEST_UNIT = (* observing a set var after stabilization *)
        let x = create_ _here_ 0 in
        set x 1;
        stabilize_ _here_;
        let o = observe (watch x) in
        stabilize_ _here_;
        assert (Observer.value_exn o = 1);
      ;;

      TEST_UNIT = (* observing and setting var after stabilization *)
        let x = create_ _here_ 0 in
        stabilize_ _here_;
        let o = observe (watch x) in
        set x 1;
        stabilize_ _here_;
        assert (Observer.value_exn o = 1);
      ;;

      TEST_UNIT = (* [set] without stabilizing *)
        let x = create_ _here_ 13 in
        assert (value x = 13);
        assert (latest_value x = 13);
        let o = observe (watch x) in
        stabilize_ _here_;
        assert (Observer.value_exn o = 13);
        set x 14;
        assert (value x = 14);
        assert (latest_value x = 14);
        assert (Observer.value_exn o = 13);
      ;;

      TEST_UNIT = (* [set] during stabilization *)
        let v0 = create_ _here_ 0 in
        let v1 = create_ _here_ 1 in
        let v2 = create_ _here_ 2 in
        let o0 = observe (watch v0) in
        let o1 =
          observe (watch v1 >>| fun i ->
                   let i0 = value v0 in
                   set v0 i;
                   assert (value v0 = i0);
                   assert (latest_value v0 = i);
                   let i2 = value v2 in
                   set v2 i;
                   assert (value v2 = i2);
                   assert (latest_value v2 = i);
                   i)
        in
        let o2 = observe (watch v2) in
        let var_values_are i0 i1 i2 =
          value v0 = i0
          && value v1 = i1
          && value v2 = i2
        in
        let observer_values_are i0 i1 i2 =
          Observer.value_exn o0 = i0
          && Observer.value_exn o1 = i1
          && Observer.value_exn o2 = i2
        in
        assert (var_values_are 0 1 2);
        stabilize_ _here_;
        assert (observer_values_are 0 1 2);
        assert (var_values_are 1 1 1);
        stabilize_ _here_;
        assert (observer_values_are 1 1 1);
        assert (var_values_are 1 1 1);
        set v1 13;
        assert (observer_values_are 1 1 1);
        assert (var_values_are 1 13 1);
        stabilize_ _here_;
        assert (observer_values_are 1 13 1);
        assert (var_values_are 13 13 13);
        stabilize_ _here_;
        assert (observer_values_are 13 13 13);
        assert (var_values_are 13 13 13);
      ;;

      TEST_UNIT = (* [set] during stabilization gets the last value that was set *)
        let x = create_ _here_ 0 in
        let o =
          observe (map (watch x) ~f:(fun v ->
            set x 1;
            set x 2;
            assert (latest_value x = 2);
            v))
        in
        stabilize_ _here_;
        assert (value x = 2);
        stabilize_ _here_;
        <:test_result< int >> (Observer.value_exn o) ~expect:2;
        disallow_future_use o;
      ;;

      TEST_UNIT = (* [create] during stabilization *)
        let o =
          observe (bind (const 13) (fun i ->
            let v = create_ _here_ i in
            watch v))
        in
        stabilize_ _here_;
        assert (Observer.value_exn o = 13);
      ;;

      TEST_UNIT = (* [create] and [set] during stabilization *)
        let o =
          observe (bind (const 13) (fun i ->
            let v = create_ _here_ i in
            let t = watch v in
            set v 15;
            t))
        in
        stabilize_ _here_;
        assert (Observer.value_exn o = 13);
      ;;

      TEST_UNIT = (* maybe invalidating a variable *)
        List.iter [ false; true ] ~f:(fun use_current_scope ->
          let lhs = Var.create 0 in
          let rhs = ref (const 0) in
          let o = observe (
            bind (watch lhs) (fun i ->
              rhs := Var.watch (create_ _here_ ~use_current_scope i);
              !rhs)) in
          stabilize_ _here_;
          let rhs = !rhs in
          assert (is_valid rhs);
          set lhs 1;
          stabilize_ _here_;
          <:test_result< bool >> (not (is_valid rhs)) ~expect:use_current_scope;
          assert (Observer.value_exn o = 1);
        )
      ;;
    end

    let am_stabilizing = am_stabilizing

    TEST = not (am_stabilizing ())

    TEST_UNIT =
      let x = Var.create_ _here_ 13 in
      let o = observe (map (watch x) ~f:(fun _ -> assert (am_stabilizing ()))) in
      stabilize_ _here_;
      disallow_future_use o;
    ;;

    let map = map
    let map2 = map2
    let map3 = map3
    let map4 = map4
    let map5 = map5
    let map6 = map6
    let map7 = map7
    let map8 = map8
    let map9 = map9

    let ( >>| ) = ( >>| )

    let test_map n (mapN : int t -> int t) =
      let o = observe (mapN (const 1)) in
      stabilize_ _here_;
      assert (value o = n);
      let x = Var.create_ _here_ 1 in
      let o = observe (mapN (watch x)) in
      stabilize_ _here_;
      assert (value o = n);
      Var.set x 0;
      stabilize_ _here_;
      assert (value o = 0);
      Var.set x 2;
      stabilize_ _here_;
      assert (value o = 2 * n);
      assert (is_invalid (mapN invalid));
      assert (is_invalidated_on_bind_rhs (fun i -> mapN (const i)));
    ;;

    TEST_UNIT = test_map 1 (fun i -> i >>| fun a1 -> a1)

    TEST_UNIT =
      test_map 1 (fun i ->
        map i ~f:(fun a1 ->
          a1))
    ;;

    TEST_UNIT =
      test_map 2 (fun i ->
        map2 i i ~f:(fun a1 a2 ->
          a1 + a2))
    ;;
    TEST_UNIT =
      test_map 3 (fun i ->
        map3 i i i ~f:(fun a1 a2 a3 ->
          a1 + a2 + a3))
    ;;
    TEST_UNIT =
      test_map 4 (fun i ->
        map4 i i i i ~f:(fun a1 a2 a3 a4 ->
          a1 + a2 + a3 + a4))
    ;;
    TEST_UNIT =
      test_map 5 (fun i ->
        map5 i i i i i ~f:(fun a1 a2 a3 a4 a5 ->
          a1 + a2 + a3 + a4 + a5))
    ;;
    TEST_UNIT =
      test_map 6 (fun i ->
        map6 i i i i i i ~f:(fun a1 a2 a3 a4 a5 a6 ->
          a1 + a2 + a3 + a4 + a5 + a6))
    ;;
    TEST_UNIT =
      test_map 7 (fun i ->
        map7 i i i i i i i ~f:(fun a1 a2 a3 a4 a5 a6 a7 ->
          a1 + a2 + a3 + a4 + a5 + a6 + a7))
    ;;
    TEST_UNIT =
      test_map 8 (fun i ->
        map8 i i i i i i i i ~f:(fun a1 a2 a3 a4 a5 a6 a7 a8 ->
          a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8))
    ;;
    TEST_UNIT =
      test_map 9 (fun i ->
        map9 i i i i i i i i i ~f:(fun a1 a2 a3 a4 a5 a6 a7 a8 a9 ->
          a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9))
    ;;

    TEST_UNIT =
      let x0 = Var.create_ _here_ 13 in
      let o0 = observe (watch x0) in
      let t1 = map (watch x0) ~f:(fun x -> x + 1) in
      let t1_o = observe t1 in
      stabilize_ _here_;
      assert (value t1_o = value o0 + 1);
      Var.set x0 14;
      stabilize_ _here_;
      assert (value t1_o = value o0 + 1);
      let x1 = Var.create_ _here_ 15 in
      let o1 = observe (watch x1) in
      let t2 = map2 (watch x0) (watch x1) ~f:(fun x y -> x + y) in
      let t2_o = observe t2 in
      let t3 = map2 t1 t2 ~f:(fun x y -> x - y) in
      let t3_o = observe t3 in
      let check () =
        stabilize_ _here_;
        assert (value t1_o = value o0 + 1);
        assert (value t2_o = value o0 + value o1);
        assert (value t3_o = value t1_o - value t2_o);
      in
      check ();
      Var.set x0 16;
      check ();
      Var.set x1 17;
      check ();
      Var.set x0 18;
      Var.set x1 19;
      check ();
    ;;

    TEST_UNIT = (* deep *)
      let rec loop i t =
        if i = 0 then t
        else loop (i - 1) (map t ~f:(fun x -> x + 1))
      in
      let x0 = Var.create_ _here_ 0 in
      let n = 100 in
      let o = observe (loop n (watch x0)) in
      stabilize_ _here_;
      assert (value o = n);
      Var.set x0 1;
      stabilize_ _here_;
      assert (value o = n + 1);
      disallow_future_use o;
      stabilize_ _here_;
    ;;

    let bind = bind
    let ( >>= ) = ( >>= )

    TEST_UNIT = (* [bind] of a constant *)
      stabilize_ _here_;
      let o = observe (const 13 >>= const) in
      stabilize_ _here_;
      assert (value o = 13);
    ;;

    TEST = is_invalidated_on_bind_rhs (fun i -> bind (const i) (fun _ -> (const i)))

    TEST_UNIT = (* bind created with an invalid rhs *)
      let o = observe (const () >>= fun () -> invalid) in
      stabilize_ _here_;
      assert (not (is_valid (Observer.observing o)));
    ;;

    TEST_UNIT = (* bind created with an rhs that becomes invalid *)
      let b = Var.create true in
      let o = observe (Var.watch b >>= fun b -> if b then const 13 else invalid) in
      stabilize_ _here_;
      Var.set b false;
      assert (is_valid (Observer.observing o));
      stabilize_ _here_;
      assert (not (is_valid (Observer.observing o)));
    ;;

    TEST_UNIT = (* an invalid node created on the rhs of a valid bind, later invalidated *)
      let x = Var.create_ _here_ 13 in
      let r = ref None in
      let o1 =
        observe (bind (Var.watch x) (fun _ ->
          r := Some (map invalid ~f:Fn.id); return ()))
      in
      stabilize_ _here_;
      let o2 = observe (Option.value_exn !r) in
      stabilize_ _here_;
      assert (not (is_valid (Observer.observing o2)));
      Var.set x 14;
      stabilize_ _here_;
      disallow_future_use o1;
      disallow_future_use o2;
    ;;

    TEST_UNIT = (* invariants blow up here if we don't make sure that we first make the
                   lhs-change node of binds necessary and only then the rhs necessary. *)
      let node1 = const () >>= return in
      let o = observe node1 in
      stabilize_ _here_;
      disallow_future_use o;
      stabilize_ _here_;
      let o = observe node1 in
      stabilize_ _here_;
      disallow_future_use o;
    ;;

    TEST_UNIT =
      let v1 = Var.create_ _here_ 0 in
      let i1 = Var.watch v1 in
      let i2 = i1 >>| fun x -> x + 1 in
      let i3 = i1 >>| fun x -> x + 2 in
      let i4 =
        i2 >>= fun x1 ->
        i3 >>= fun x2 ->
        const (x1 + x2)
      in
      let o4 = observe i4 in
      List.iter (List.init 20 ~f:Fn.id) ~f:(fun x ->
        Gc.full_major ();
        Var.set v1 x;
        stabilize_ _here_;
        assert (Observer.value_exn o4 = 2 * x + 3))
    ;;

    TEST_UNIT = (* graph changes only *)
      let x = Var.create_ _here_ true in
      let a = const 3 in
      let b = const 4 in
      let o = observe (bind (watch x) (fun bool -> if bool then a else b)) in
      let check where expect =
        stabilize_ where;
        <:test_eq< int >> (value o) expect;
      in
      check _here_ 3;
      Var.set x false;
      check _here_ 4;
      Var.set x true;
      check _here_ 3;
    ;;

    TEST_UNIT =
      let x0 = Var.create_ _here_ 13 in
      let o0 = observe (watch x0) in
      let x1 = Var.create_ _here_ 15 in
      let o1 = observe (watch x1) in
      let x2 = Var.create_ _here_ true in
      let o2 = observe (watch x2) in
      let t = bind (watch x2) (fun b -> if b then watch x0 else watch x1) in
      let t_o = observe t in
      let check () =
        stabilize_ _here_;
        assert (value t_o = value (if value o2 then o0 else o1));
      in
      check ();
      Var.set x0 17;
      check ();
      Var.set x1 19;
      check ();
      Var.set x2 false;
      check ();
      Var.set x0 21;
      Var.set x2 true;
      check ();
    ;;

    TEST_UNIT = (* walking chains of maps is not allowed to cross scopes *)
      let x0 = Var.create_ _here_ 0 in
      let x1 = Var.create_ _here_ 1 in
      let r = ref 0 in
      let i2 =
        observe (Var.watch x0 >>= (fun i -> Var.watch x1 >>| fun _ -> incr r; i))
      in
      assert (!r = 0);
      stabilize_ _here_;
      assert (!r = 1);
      assert (value i2 = 0);
      Var.set x0 10;
      Var.set x1 11;
      stabilize_ _here_;
      assert (!r = 2);
      assert (value i2 = 10);
    ;;

    TEST_UNIT =
      let v1 = Var.create_ _here_ 0 in
      let i1 = Var.watch v1 in
      let o1 = observe i1 in
      Var.set v1 1;
      let i2 = i1 >>= fun _ -> i1 in
      let o2 = observe i2 in
      stabilize_ _here_;
      Var.set v1 2;
      stabilize_ _here_;
      Gc.keep_alive (i1, i2, o1, o2);
    ;;

    TEST_UNIT = (* topological overload many *)
      let rec copy_true c1 = bind c1 (fun x -> if x then c1           else copy_false c1)
      and    copy_false c1 = bind c1 (fun x -> if x then copy_true c1 else c1           )
      in
      let x1 = Var.create_ _here_ false in
      let rec loop cur i =
        if i > 1000
        then cur
        else loop (copy_true (copy_false cur)) (i+1)
      in
      let hold = loop (Var.watch x1) 0 in
      let rec set_loop at i =
        if i < 5 then (Var.set x1 at; stabilize_ _here_; set_loop (not at) (i + 1))
      in
      set_loop true 0;
      Gc.keep_alive hold;
    ;;

    TEST_UNIT = (* nested var sets *)
      (* We model a simple ETF that initially consists of 100 shares of IBM and 200 shares
         of microsoft with an implicit divisor of 1. *)
      (* the last trade prices of two stocks *)
      let ibm = Var.create_ _here_ 50. in
      let msft = Var.create_ _here_ 20. in
      (* .5 shares of IBM, .5 shares of MSFT.  Divisor implicitly 1. *)
      let cfg = Var.create_ _here_ (0.5, 0.5) in
      let nav =
        observe
          (bind (Var.watch cfg) (fun (ibm_mult, msft_mult) ->
             let x = map (Var.watch ibm) ~f:(fun ibm -> ibm *. ibm_mult) in
             let y = map (Var.watch msft) ~f:(fun msft -> msft *. msft_mult) in
             sum [| x; y |] ~zero:0. ~add:(+.) ~sub:(-.)
           ))
      in
      stabilize_ _here_;
      assert (value nav =. 0.5 *. 50. +. 0.5 *. 20.);
      Var.set cfg (0.6, 0.4);
      stabilize_ _here_;
      assert (value nav =. 0.6 *. 50. +. 0.4 *. 20.);
    ;;

    TEST_UNIT = (* adjust heights *)
      let x = Var.create_ _here_ 0 in
      let rec chain i =
        if i = 0
        then watch x
        else chain (i - 1) >>| fun i -> i + 1
      in
      let b = bind (watch x) chain in
      let rec dag i =
        if i = 0
        then b
        else
          let t = dag (i - 1) in
          map2 t t ~f:( + )
      in
      let o = observe (dag 20) in
      for i = 1 to 10 do
        Var.set x i;
        stabilize_ _here_;
      done;
      disallow_future_use o;
    ;;

    let make_high t =
      let rec loop t n =
        if n = 0 then t else loop (map2 t t ~f:(fun a _ -> a)) (n - 1)
      in
      loop t 5
    ;;

    TEST_UNIT = (* an invalid unused rhs doesn't invalidate the [bind] *)
      let r = ref None in
      let lhs = Var.create_ _here_ 1; in
      let o1 = observe (bind (watch lhs) (fun i -> r := Some (const i); return ())) in
      stabilize_ _here_;
      let else_ = Option.value_exn !r in
      let test = Var.create_ _here_ false in
      let o2 = observe (bind (make_high (watch test))
                          (fun test ->
                             if test then const 13 else else_))
      in
      stabilize_ _here_;
      Var.set lhs 2; (* invalidates [else_]. *)
      Var.set test true;
      stabilize_ _here_;
      assert (not (is_valid else_));
      assert (value o2 = 13);
      disallow_future_use o1;
      disallow_future_use o2;
    ;;

    TEST_UNIT = (* plugging an invalid node in a bind can invalidate the bind (though
                   not always) *)
      let x = Var.create 4 in
      let r = ref (const (-1)) in
      let o = observe (Var.watch x >>= fun i -> r := const i; const ()) in
      stabilize_ _here_;
      let escaped = !r in
      let escaped_o = observe escaped in
      stabilize_ _here_;
      assert (Observer.value_exn escaped_o = 4);
      Var.set x 5;
      stabilize_ _here_;
      assert (not (is_valid escaped));
      disallow_future_use o;
      let o = observe (Var.watch x >>= fun _ -> escaped) in
      stabilize_ _here_;
      disallow_future_use o;
      disallow_future_use escaped_o;
    ;;

    TEST_UNIT = (* changing the rhs from a node to its ancestor, which causes problems if
                   we leave the node with a broken invariant while adding the ancestor. *)
      let lhs_var = Var.create false in
      let num_calls = ref 0 in
      let rhs_var = Var.create 13 in
      let rhs_false = map (watch rhs_var) ~f:(fun i -> incr num_calls; i + 1) in
      let rhs_true  = map rhs_false ~f:(fun i -> i + 1) in
      let o =
        observe (bind (watch lhs_var) (fun b -> if b then rhs_true else rhs_false))
      in
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
      Var.set lhs_var true;
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
      disallow_future_use o;
      stabilize_ _here_;
      Var.set rhs_var 14;
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
    ;;

    let bind2 = bind2
    let bind3 = bind3
    let bind4 = bind4

    TEST_UNIT =
      let v1 = Var.create_ _here_ 1 in
      let v2 = Var.create_ _here_ 2 in
      let v3 = Var.create_ _here_ 3 in
      let v4 = Var.create_ _here_ 4 in
      let o =
        observe
          (bind4 (watch v1) (watch v2) (watch v3) (watch v4) (fun x1 x2 x3 x4 ->
             bind3 (watch v2) (watch v3) (watch v4) (fun y2 y3 y4 ->
               bind2 (watch v3) (watch v4) (fun z3 z4 ->
                 bind (watch v4) (fun w4 ->
                   return (x1 + x2 + x3 + x4 + y2 + y3 + y4 + z3 + z4 + w4))))))
      in
      let check where =
        stabilize_ where;
        <:test_result< int >> (value o)
          ~expect:(Var.value v1
                   + 2 * Var.value v2
                   + 3 * Var.value v3
                   + 4 * Var.value v4);
      in
      check _here_;
      Var.set v4 5;
      check _here_;
      Var.set v3 6;
      check _here_;
      Var.set v2 7;
      check _here_;
      Var.set v1 8;
      check _here_;
      Var.set v1 9;
      Var.set v2 10;
      Var.set v3 11;
      Var.set v4 12;
      check _here_;
    ;;

    let join = join

    TEST_UNIT = (* [join] of a constant *)
      let o = observe (join (const (const 1))) in
      stabilize_ _here_;
      assert (value o = 1);
    ;;

    TEST_UNIT = (* graph changes only *)
      let a = const 3 in
      let b = const 4 in
      let x = Var.create_ _here_ a in
      let o = observe (join (watch x)) in
      let check where expect =
        stabilize_ where;
        <:test_result< int >> (value o) ~expect;
      in
      check _here_ 3;
      Var.set x b;
      check _here_ 4;
      Var.set x a;
      check _here_ 3;
    ;;

    TEST_UNIT =
      let v1 = Var.create_ _here_ 1 in
      let v2 = Var.create_ _here_ 2 in
      let v3 = Var.create_ _here_ (Var.watch v1) in
      let o = observe (join (Var.watch v3)) in
      stabilize_ _here_;
      assert (value o = 1);
      Var.set v1 13;
      stabilize_ _here_;
      assert (value o = 13);
      Var.set v3 (Var.watch v2);
      stabilize_ _here_;
      assert (value o = 2);
      Var.set v3 (Var.watch v1);
      Var.set v1 14;
      stabilize_ _here_;
      assert (value o = 14);
    ;;

    TEST_UNIT = (* an invalid unused rhs doesn't invalidate the [join] *)
      let x = Var.create_ _here_ (const 0); in
      let lhs = Var.create_ _here_ 1 in
      let o1 = observe (bind (watch lhs) (fun i -> Var.set x (const i); return ())) in
      stabilize_ _here_;
      let o2 = observe (join (make_high (Var.watch x))) in
      stabilize_ _here_;
      Var.set lhs 2; (* invalidate *)
      Var.set x (const 3);
      stabilize_ _here_;
      assert (value o2 = 3);
      disallow_future_use o1;
      disallow_future_use o2;
    ;;

    TEST_UNIT = (* checking that join can be invalidated *)
      let join = join (const invalid) in
      let o = observe join in
      stabilize_ _here_;
      disallow_future_use o;
      assert (not (is_valid join));
    ;;

    TEST_UNIT = (* changing the rhs from a node to its ancestor, which causes problems if
                   we leave the node with a broken invariant while adding the ancestor. *)
      let num_calls = ref 0 in
      let rhs_var = Var.create 13 in
      let first = map (watch rhs_var) ~f:(fun i -> incr num_calls; i + 1) in
      let second  = map first ~f:(fun i -> i + 1) in
      let lhs_var = Var.create first in
      let o = observe (join (watch lhs_var)) in
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
      Var.set lhs_var second;
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
      disallow_future_use o;
      stabilize_ _here_;
      Var.set rhs_var 14;
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
    ;;

    let if_ = if_

    TEST_UNIT = (* [if_ true] *)
      let o = observe (if_ (const true) ~then_:(const 13) ~else_:(const 14)) in
      stabilize_ _here_;
      assert (value o = 13);
    ;;

    TEST_UNIT = (* [if_ false] *)
      let o = observe (if_ (const false) ~then_:(const 13) ~else_:(const 14)) in
      stabilize_ _here_;
      assert (value o = 14);
    ;;

    TEST_UNIT = (* graph changes only *)
      let x = Var.create_ _here_ true in
      let o = observe (if_ (watch x) ~then_:(const 3) ~else_:(const 4)) in
      let check where expect =
        stabilize_ where;
        <:test_eq< int >> (value o) expect;
      in
      check _here_ 3;
      Var.set x false;
      check _here_ 4;
      Var.set x true;
      check _here_ 3;
      Var.set x false;
      check _here_ 4;
    ;;

    TEST_UNIT =
      let test = Var.create_ _here_ true in
      let then_ = Var.create_ _here_ 1 in
      let else_ = Var.create_ _here_ 2 in
      let num_then_run = ref 0 in
      let num_else_run = ref 0 in
      let ite =
        observe (if_ (Var.watch test)
                   ~then_:(Var.watch then_ >>| fun i -> incr num_then_run; i)
                   ~else_:(Var.watch else_ >>| fun i -> incr num_else_run; i))
      in
      stabilize_ _here_;
      assert (Observer.value_exn ite = 1);
      assert (!num_then_run = 1);
      assert (!num_else_run = 0);
      Var.set test false;
      stabilize_ _here_;
      assert (Observer.value_exn ite = 2);
      Var.set test true;
      stabilize_ _here_;
      assert (Observer.value_exn ite = 1);
      Var.set then_ 3;
      Var.set else_ 4;
      let ntr = !num_then_run in
      let ner = !num_else_run in
      stabilize_ _here_;
      assert (Observer.value_exn ite = 3);
      assert (!num_then_run = ntr + 1);
      assert (!num_else_run = ner);
      Var.set test false;
      Var.set then_ 5;
      Var.set else_ 6;
      stabilize_ _here_;
      assert (Observer.value_exn ite = 6);
    ;;

    TEST_UNIT = (* an invalid unused branch doesn't invalidate the [if_] *)
      let r = ref None in
      let lhs = Var.create_ _here_ 1; in
      let o1 = observe (bind (watch lhs) (fun i -> r := Some (const i); return ())) in
      stabilize_ _here_;
      let else_ = Option.value_exn !r in
      let test = Var.create_ _here_ false in
      let o2 = observe (if_ (make_high (watch test)) ~then_:(const 13) ~else_) in
      stabilize_ _here_;
      Var.set lhs 2; (* invalidates [else_]. *)
      Var.set test true;
      stabilize_ _here_;
      assert (not (is_valid else_));
      assert (value o2 = 13);
      disallow_future_use o1;
      disallow_future_use o2;
    ;;

    TEST_UNIT = (* if-then-else created with an invalid test *)
      let o =
        observe (if_ (invalid >>| fun _ -> true) ~then_:(const ()) ~else_:(const ()))
      in
      stabilize_ _here_;
      assert (not (is_valid (Observer.observing o)));
    ;;

    TEST_UNIT = (* if-then-else created with an invalid branch *)
      let o = observe (if_ (const true) ~then_:invalid ~else_:(const 13)) in
      stabilize_ _here_;
      assert (not (is_valid (Observer.observing o)));
    ;;

    TEST_UNIT = (* if-then-else switching to an invalid branch *)
      let b = Var.create false in
      let o = observe (if_ (Var.watch b) ~then_:invalid ~else_:(const 13)) in
      stabilize_ _here_;
      assert (is_valid (Observer.observing o));
      Var.set b true;
      stabilize_ _here_;
      assert (not (is_valid (Observer.observing o)));
    ;;

    TEST_UNIT = (* if-then-else switching to an invalid branch via a map *)
      let b = Var.create false in
      let o = observe (if_ (Var.watch b)
                         ~then_:(invalid >>| fun _ -> 13)
                         ~else_:(const 13))
      in
      stabilize_ _here_;
      assert (is_valid (Observer.observing o));
      Var.set b true;
      stabilize_ _here_;
      assert (not (is_valid (Observer.observing o)));
    ;;

    TEST_UNIT = (* if-then-else switching to an invalid test *)
      let b = Var.create false in
      let o = observe (if_ (if_ (Var.watch b)
                              ~then_:(invalid >>| fun _ -> true)
                              ~else_:(const true))
                         ~then_:(const 13)
                         ~else_:(const 15))
      in
      stabilize_ _here_;
      assert (is_valid (Observer.observing o));
      Var.set b true;
      stabilize_ _here_;
      assert (not (is_valid (Observer.observing o)));
    ;;

    TEST_UNIT = (* changing branches from a node to its ancestor, which causes problems if
                   we leave the node with a broken invariant while adding the ancestor. *)
      let test_var = Var.create false in
      let num_calls = ref 0 in
      let branch_var = Var.create 13 in
      let else_ = map (watch branch_var) ~f:(fun i -> incr num_calls; i + 1) in
      let then_  = map else_ ~f:(fun i -> i + 1) in
      let o = observe (if_ (watch test_var) ~then_ ~else_) in
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
      Var.set test_var true;
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
      disallow_future_use o;
      stabilize_ _here_;
      Var.set branch_var 14;
      stabilize_ _here_;
      <:test_result< int >> !num_calls ~expect:1;
    ;;

    let freeze = freeze

    TEST_UNIT =
      let x = Var.create_ _here_ 13 in
      let f = freeze (Var.watch x) in
      let y = observe f in
      assert (not (is_const f));
      stabilize_ _here_;
      assert (value y = 13);
      assert (is_const f);
      let u = Var.create_ _here_ 1 in
      let z = observe (bind (Var.watch u) (fun _ -> freeze (Var.watch x))) in
      stabilize_ _here_;
      assert (value z = 13);
      Var.set u 2;
      Var.set x 14;
      stabilize_ _here_;
      assert (value z = 14);
      Var.set x 15;
      stabilize_ _here_;
      assert (value z = 14);
      Var.set u 3;
      stabilize_ _here_;
      assert (value z = 15);
    ;;

    TEST_UNIT =
      let x = Var.create_ _here_ 13 in
      let o1 = observe (freeze (Var.watch x >>| Fn.id)) in
      let o2 = observe (Var.watch x >>| Fn.id) in
      stabilize_ _here_;
      assert (value o1 = 13);
      assert (value o2 = 13);
      stabilize_ _here_;
      assert (value o1 = 13);
      assert (value o2 = 13);
      Var.set x 14;
      stabilize_ _here_;
      assert (value o1 = 13);
      assert (value o2 = 14);
    ;;

    TEST_UNIT = (* [freeze] nodes increment [num_nodes_became_necessary] *)
      let i1 = State.(num_nodes_became_necessary t) in
      ignore (freeze (const ()) : unit t);
      let i2 = State.(num_nodes_became_necessary t) in
      <:test_result< int >> i2
        ~expect:(i1 + 2); (* one for the [const], one for the [freeze] *)
    ;;

    (* TEST_UNIT = (\* freeze nodes leak memory (and forces spurious computations) until
     *                they freeze *\)
     *   let c = const () in
     *   for i = 0 to 100_000_000 do
     *     ignore (freeze c ~when_:(fun () -> false) : unit t);
     *     if i mod 1000 = 0 then begin
     *       Printf.printf "num parents %d\n%!" ((Obj.magic c : int array).(7));
     *       stabilize_ _here_;
     *     end
     *   done;
     * ;; *)

    TEST_UNIT = (* [freeze]ing something that is otherwise unnecessary. *)
      let x = Var.create_ _here_ 0 in
      let i = freeze (Var.watch x >>| fun i -> i + 1) in
      stabilize_ _here_;
      Var.set x 13;
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 1);  (* not 14 *)
    ;;

    TEST_UNIT = (* a frozen node remains valid, even if its original scope isn't *)
      let x = Var.create_ _here_ 13 in
      let r = ref None in
      let o1 =
        observe (watch x
                 >>= fun i ->
                 if Option.is_none !r then r := Some (freeze (const i));
                 const ())
      in
      stabilize_ _here_;
      let f = Option.value_exn !r in
      Var.set x 15;
      stabilize_ _here_;
      let o2 = observe f in
      stabilize_ _here_;
      assert (is_const f);
      assert (value o2 = 13);
      disallow_future_use o1;
      stabilize_ _here_;
    ;;

    TEST_UNIT = (* a frozen node remains valid, even if the node it froze isn't *)
      let x = Var.create_ _here_ 13 in
      let r = ref (const 14) in
      let o1 = observe (watch x >>= fun i -> r := (const i); const ()) in
      stabilize_ _here_;
      let o2 = observe (freeze !r) in
      stabilize_ _here_;
      Var.set x 15;
      stabilize_ _here_;
      assert (value o2 = 13);
      disallow_future_use o1;
    ;;

    TEST_UNIT = (* [freeze ~when] *)
      let x = Var.create_ _here_ 13 in
      let o = observe (freeze (watch x) ~when_:(fun i -> i >= 15)) in
      let check where expect =
        stabilize_ where;
        <:test_result< int >> (value o) ~expect;
      in
      check _here_ 13;
      Var.set x 14;
      check _here_ 14;
      Var.set x 15;
      check _here_ 15;
      Var.set x 16;
      check _here_ 15;
      Var.set x 14;
      check _here_ 15;
    ;;

    TEST_UNIT = (* a freeze that is invalidated before it is frozen. *)
      let r = ref None in
      let x = Var.create_ _here_ 13 in
      let o = observe (bind (watch x) (fun i -> r := Some (const i); return ())) in
      stabilize_ _here_;
      let f = freeze (Option.value_exn !r) ~when_:(fun _ -> false) in
      Var.set x 14;
      stabilize_ _here_;
      assert (not (is_valid f));
      disallow_future_use o;
    ;;

    TEST_UNIT = (* a freeze that is stabilized and invalidated before it is frozen. *)
      let r = ref None in
      let x = Var.create_ _here_ 13 in
      let o = observe (bind (watch x) (fun i -> r := Some (const i); return ())) in
      stabilize_ _here_;
      let f = freeze (Option.value_exn !r) ~when_:(fun _ -> false) in
      stabilize_ _here_;
      Var.set x 14;
      stabilize_ _here_;
      assert (not (is_valid f));
      disallow_future_use o;
    ;;

    let depend_on = depend_on

    TEST_UNIT =
      let x = Var.create_ _here_ 13 in
      let y = Var.create_ _here_ 14 in
      let d = depend_on (watch x) ~depend_on:(watch y) in
      let o = observe d in
      let nx = ref 0 in
      let incr_o r =
        function
        | Observer.Update.Invalidated -> assert false
        | Initialized _ | Changed _ -> incr r
      in
      let incr r =
        function
        | Update.Invalidated -> assert false
        | Unnecessary -> ()
        | Necessary _ | Changed _ -> incr r
      in
      Observer.on_update_exn o ~f:(incr_o nx);
      let ny = ref 0 in
      on_update (Var.watch y) ~f:(incr ny);
      let check where eo enx eny =
        stabilize_ where;
        <:test_result< int >> (value o) ~expect:eo;
        <:test_result< int >> !nx ~expect:enx;
        <:test_result< int >> !ny ~expect:eny;
      in
      check _here_ 13 1 1;
      Var.set x 15;
      check _here_ 15 2 1;
      Var.set y 16;
      check _here_ 15 2 2;
      Var.set x 17;
      Var.set y 18;
      check _here_ 17 3 3;
      Var.set x 17;
      check _here_ 17 3 3;
      Var.set y 18;
      check _here_ 17 3 3;
      disallow_future_use o;
      let check where enx eny =
        stabilize_ where;
        <:test_result< int >> !nx ~expect:enx;
        <:test_result< int >> !ny ~expect:eny;
      in
      Var.set x 19;
      Var.set y 20;
      check _here_ 3 3;
      let o = observe d in
      Observer.on_update_exn o ~f:(incr_o nx);
      check _here_ 4 4;
      <:test_result< int >> (value o) ~expect:19;
    ;;

    TEST_UNIT = (* propagating the first argument of [depend_on] while the result of
                   [depend_on] is not observable *)
      let var = Var.create 1 in
      let depend = depend_on (Var.watch var) ~depend_on:(const ()) in
      let o = observe depend in
      stabilize_ _here_;
      assert (Observer.value_exn o = 1);
      disallow_future_use o;
      let o = observe (Var.watch var) in
      Var.set var 2;
      stabilize_ _here_;
      assert (Observer.value_exn o = 2);
      disallow_future_use o;
      let o = observe depend in
      stabilize_ _here_;
      <:test_eq< int >> (Observer.value_exn o) 2;
    ;;

    TEST_UNIT = (* depend_on doesn't cutoff using phys_equal *)
      let v1 = Var.create () in
      let v2 = Var.create 1 in
      set_cutoff (Var.watch v1) Cutoff.never;
      let o = observe (depend_on (Var.watch v1) ~depend_on:(Var.watch v2)) in
      let updates = ref 0 in
      Observer.on_update_exn o ~f:(fun _ -> incr updates);
      <:test_eq< int >> !updates 0;
      stabilize_ _here_;
      <:test_eq< int >> !updates 1;
      Var.set v2 2;
      stabilize_ _here_;
      <:test_eq< int >> !updates 1;
      Var.set v1 ();
      stabilize_ _here_;
      <:test_eq< int >> !updates 2;
      disallow_future_use o;
    ;;

    let necessary_if_alive = necessary_if_alive

    TEST_UNIT = (* dead => unnecessary *)
      let x = Var.create 13 in
      let push, check = on_update_queue () in
      on_update (watch x) ~f:push;
      stabilize_ _here_;
      check [ Unnecessary ];
      let t = necessary_if_alive (watch x) in
      stabilize_ _here_;
      check [ Necessary 13 ];
      Var.set x 14;
      stabilize_ _here_;
      check [ Changed (13, 14) ];
      Gc.keep_alive t;
      Gc.full_major ();
      stabilize_ _here_;
      check [ Unnecessary ];
    ;;

    TEST_UNIT = (* cutoff is preserved *)
      let x = Var.create 13 in
      set_cutoff (watch x) Cutoff.never;
      let t = necessary_if_alive (watch x) in
      let o = observe t in
      let push, check = on_update_queue () in
      on_update t ~f:push;
      stabilize_ _here_;
      check [ Necessary 13 ];
      Var.set x 14;
      stabilize_ _here_;
      check [ Changed (13, 14) ];
      Var.set x 14;
      stabilize_ _here_;
      check [ Changed (14, 14) ];
      disallow_future_use o;
      Gc.full_major ();
      stabilize_ _here_;
      check [ Unnecessary ];
    ;;

    let all     = all
    let exists  = exists
    let for_all = for_all

    let test q list_f =
      for num_vars = 0 to 3 do
        let vars = List.init num_vars ~f:(fun _ -> Var.create_ _here_ true) in
        let q = observe (q (Array.of_list_map vars ~f:watch)) in
        let all = observe (all (List.map vars ~f:watch)) in
        let rec loop vars =
          match vars with
          | [] ->
            stabilize_ _here_;
            <:test_eq< Bool.t >> (value q) (list_f (value all) ~f:Fn.id);
          | var :: vars ->
            List.iter [ false; true ] ~f:(fun b -> Var.set var b; loop vars)
        in
        loop vars;
      done;
    ;;

    TEST_UNIT = test exists  List.exists
    TEST_UNIT = test for_all List.for_all

    let array_fold = array_fold

    TEST_UNIT = (* empty array *)
      let o = observe (array_fold [||] ~init:13 ~f:(fun _ -> assert false)) in
      stabilize_ _here_;
      assert (value o = 13);
    ;;

    TEST_UNIT =
      let x = Var.create_ _here_ 13 in
      let y = Var.create_ _here_ 14 in
      let o =
        observe (array_fold [| watch y; watch x |] ~init:[] ~f:(fun ac x -> x :: ac))
      in
      let check where expect =
        stabilize_ where;
        <:test_result< int list >> (value o) ~expect;
      in
      check _here_ [ 13; 14 ];
      Var.set x 15;
      check _here_ [ 15; 14 ];
      Var.set y 16;
      check _here_ [ 15; 16 ];
      Var.set x 17;
      Var.set y 18;
      check _here_ [ 17; 18 ];
    ;;

    let unordered_array_fold = unordered_array_fold

    TEST_UNIT = (* empty array *)
      let o =
        observe (unordered_array_fold ~full_compute_every_n_changes:0 [||] ~init:13
                   ~f:(fun _ -> assert false)
                   ~f_inverse:(fun _ -> assert false))
      in
      stabilize_ _here_;
      assert (value o = 13);
    ;;

    TEST_UNIT = (* an unnecessary [unordered_array_fold] isn't computed. *)
      let x = Var.create_ _here_ 1 in
      let num_f_inverse = ref 0 in
      let ox = observe (Var.watch x) in
      let fold =
        unordered_array_fold [| Var.watch x |]
          ~init:0
          ~f:(+)
          ~f_inverse:(fun b a ->
            incr num_f_inverse;
            b - a)
      in
      let r = observe fold in
      stabilize_ _here_;
      assert (value r = 1);
      assert (!num_f_inverse = 0);
      Var.set x 2;
      stabilize_ _here_;
      assert (value r = 2);
      assert (!num_f_inverse = 1);
      disallow_future_use r;
      Var.set x 3;
      stabilize_ _here_;
      assert (!num_f_inverse = 1);
      assert (value ox = 3);
      let r = observe fold in
      stabilize_ _here_;
      <:test_result< int >> (value r) ~expect:3;
      assert (!num_f_inverse = 1);
    ;;

    TEST_UNIT = (* multiple occurences of a node in the fold. *)
      let x = Var.create_ _here_ 1 in
      let f = unordered_array_fold [| watch x; watch x |] ~init:0 ~f:(+) ~f_inverse:(-) in
      let o = observe f in
      stabilize_ _here_;
      assert (value o = 2);
      Var.set x 3;
      stabilize_ _here_;
      assert (value o = 6);
      disallow_future_use o;
      stabilize_ _here_;
      Var.set x 4;
      stabilize_ _here_;
      let o = observe f in
      stabilize_ _here_;
      assert (value o = 8);
    ;;

    let opt_unordered_array_fold = opt_unordered_array_fold

    TEST_UNIT =
      let o = observe (opt_unordered_array_fold [||]
                         ~init:()
                         ~f:(fun _ -> assert false)
                         ~f_inverse:(fun _ -> assert false))
      in
      stabilize_ _here_;
      assert (is_some (value o));
    ;;

    TEST_UNIT =
      let x = Var.create_ _here_ None in
      let y = Var.create_ _here_ None in
      let t =
        observe (opt_unordered_array_fold [| watch x; watch y |]
                   ~init:0 ~f:( + ) ~f_inverse:( - ))
      in
      let check where expect =
        stabilize_ where;
        <:test_eq< int option >> (value t) expect;
      in
      check _here_ None;
      Var.set x (Some 13);
      check _here_ None;
      Var.set y (Some 14);
      check _here_ (Some 27);
      Var.set y None;
      check _here_ None;
    ;;

    let sum = sum

    TEST_UNIT = (* empty *)
      let o = observe (sum [||] ~zero:13 ~add:(fun _ -> assert false)
                         ~sub:(fun _ -> assert false))
      in
      stabilize_ _here_;
      assert (value o = 13);
    ;;

    TEST_UNIT = (* full recompute *)
      let x = Var.create_ _here_ 13. in
      let y = Var.create_ _here_ 15. in
      let num_adds = ref 0 in
      let add a b = incr num_adds; a +. b in
      let num_subs = ref 0 in
      let sub a b = incr num_subs; a -. b in
      let z =
        observe
          (sum [| watch x; watch y |] ~zero:0. ~add ~sub
             ~full_compute_every_n_changes:2)
      in
      stabilize_ _here_;
      assert (!num_adds = 2);
      assert (!num_subs = 0);
      assert (Float.equal (value z) 28.);
      Var.set x 17.;
      stabilize_ _here_;
      assert (!num_adds = 3);
      assert (!num_subs = 1);
      assert (Float.equal (value z) 32.);
      Var.set y 19.;
      stabilize_ _here_;
      (* [num_adds] increases 2 for the full recompute.  [num_subs] doesn't change because
         of the full recompute. *)
      <:test_result< int >> !num_adds ~expect:5;
      <:test_result< int >> !num_subs ~expect:1;
      assert (Float.equal (value z) 36.);
    ;;

    let opt_sum = opt_sum

    TEST_UNIT =
      let t =
        observe (opt_sum [||] ~zero:()
                   ~add:(fun _ -> assert false)
                   ~sub:(fun _ -> assert false))
      in
      stabilize_ _here_;
      assert (is_some (value t));
    ;;

    TEST_UNIT =
      let x = Var.create_ _here_ None in
      let y = Var.create_ _here_ None in
      let t = observe (opt_sum [| watch x; watch y |] ~zero:0 ~add:( + ) ~sub:( - )) in
      let check where expect =
        stabilize_ where;
        <:test_eq< int option >> (value t) expect;
      in
      check _here_ None;
      Var.set x (Some 13);
      check _here_ None;
      Var.set y (Some 14);
      check _here_ (Some 27);
      Var.set y None;
      check _here_ None;
    ;;

    let sum_int    = sum_int
    let sum_float  = sum_float

    let test_sum (type a) sum (of_int : int -> a) equal =
      let x = Var.create_ _here_ (of_int 13) in
      let y = Var.create_ _here_ (of_int 15) in
      let z = observe (sum [| watch x; watch y |]) in
      stabilize_ _here_;
      assert (equal (value z) (of_int 28));
      stabilize_ _here_;
      Var.set x (of_int 17);
      stabilize_ _here_;
      assert (equal (value z) (of_int 32));
      Var.set x (of_int 19);
      Var.set y (of_int 21);
      stabilize_ _here_;
      assert (equal (value z) (of_int 40));
    ;;

    TEST_UNIT = test_sum sum_int   Fn.id        Int.equal
    TEST_UNIT = test_sum sum_float Float.of_int Float.equal

    TEST_UNIT =
      let o = observe (sum_float [||]) in
      stabilize_ _here_;
      <:test_result< Float.t >> (value o) ~expect:0.;
    ;;

    let alarm_precision = alarm_precision (* nothing to test? *)

    let now           = now
    let watch_now     = watch_now
    let advance_clock = advance_clock

    TEST_UNIT =
      let w = observe (watch_now ()) in
      stabilize_ _here_;
      let before_advance = now () in
      assert (Time.equal before_advance (value w));
      let to_ = Time.add before_advance (sec 1.) in
      advance_clock ~to_;
      assert (Time.equal (now ()) to_);
      assert (Time.equal (value w) before_advance); (* because we didn't yet stabilize *)
      stabilize_ _here_;
      assert (Time.equal (value w) to_);
    ;;

    let after = after
    let at    = at

    let is observer v = Poly.equal (value observer) v

    TEST = is_invalidated_on_bind_rhs (fun _ -> at (Time.add (Time.now ()) (sec 1.)))
    TEST = is_invalidated_on_bind_rhs (fun _ -> at (Time.add (Time.now ()) (sec (-1.))))
    TEST = is_invalidated_on_bind_rhs (fun _ -> after (sec 1.))
    TEST = is_invalidated_on_bind_rhs (fun _ -> after (sec (-1.)))

    TEST_UNIT =
      let now = now () in
      let at span = observe (at (Time.add now span)) in
      let i1 = at (sec (-1.)) in
      let i2 = at (sec (-0.1)) in
      let i3 = at (sec 1.) in
      stabilize_ _here_;
      assert (is i1 After);
      assert (is i2 After);
      assert (is i3 Before);
      advance_clock_by (sec 0.5);
      stabilize_ _here_;
      assert (is i1 After);
      assert (is i2 After);
      assert (is i3 Before);
      advance_clock_by (sec 1.);
      stabilize_ _here_;
      assert (is i1 After);
      assert (is i2 After);
      assert (is i3 After);
    ;;

    TEST_UNIT = (* advancing the clock in the same stabilization cycle as creation *)
      let i = observe (after (sec 1.)) in
      advance_clock_by (sec 2.);
      stabilize_ _here_;
      assert (is i After);
    ;;

    TEST_UNIT = (* firing an unnecessary [after] and then observing it *)
      let i = after (sec (-1.)) in
      stabilize_ _here_;
      let o = observe i in
      stabilize_ _here_;
      assert (is o After);
      let r = ref 0 in
      let i = after (sec 1.) >>| fun z -> incr r; z in
      advance_clock_by (sec 2.);
      stabilize_ _here_;
      assert (!r = 0);
      stabilize_ _here_;
      let o = observe i in
      stabilize_ _here_;
      assert (!r = 1);
      assert (is o After);
    ;;

    let at_intervals = at_intervals

    TEST = does_raise (fun () -> at_intervals (sec (-1.)))
    TEST = does_raise (fun () -> at_intervals (sec 0.))

    TEST = is_invalidated_on_bind_rhs (fun _ -> at_intervals (sec 1.))

    TEST_UNIT = (* advancing the clock does nothing by itself *)
      let r = ref 0 in
      let i = at_intervals (sec 1.) >>| fun () -> incr r in
      let o = observe i in
      assert (!r = 0);
      advance_clock_by (sec 2.);
      assert (!r = 0);
      disallow_future_use o;
    ;;

    TEST_UNIT =
      let r = ref (-1) in
      let i = at_intervals (sec 1.) >>| fun () -> incr r in
      let o = observe i in
      stabilize_ _here_;
      assert (!r = 0);
      advance_clock_by (sec 0.5);
      stabilize_ _here_;
      assert (!r = 1);
      advance_clock_by (sec 1.);
      stabilize_ _here_;
      assert (!r = 2);
      advance_clock_by (sec 1.);
      assert (!r = 2);
      advance_clock_by (sec 1.);
      assert (!r = 2);
      advance_clock_by (sec 1.);
      assert (!r = 2);
      stabilize_ _here_;
      assert (!r = 3);
      advance_clock_by (sec 10.);
      stabilize_ _here_;
      assert (!r = 4);
      disallow_future_use o;
      advance_clock_by (sec 2.);
      stabilize_ _here_;
      assert (!r = 4);
      let o = observe i in
      stabilize_ _here_;
      assert (!r = 5);
      disallow_future_use o;
    ;;

    TEST_UNIT = (* advancing exactly to intervals doesn't skip any *)
      let r = ref (-1) in
      let o = observe (at_intervals (sec 1.) >>| fun () -> incr r) in
      stabilize_ _here_;
      <:test_result< int >> !r ~expect:0;
      let base = now () in
      let curr = ref base in
      for i = 1 to 20 do
        curr := Time.next_multiple ~base ~after:!curr ~interval:(sec 1.) ();
        advance_clock ~to_:!curr;
        stabilize_ _here_;
        <:test_result< int >> !r ~expect:i;
      done;
      disallow_future_use o;
    ;;

    TEST_UNIT = (* [interval < alarm precision] raises *)
      assert (does_raise (fun () -> at_intervals (sec 0.0005)));
    ;;

    let snapshot = snapshot

    TEST_UNIT = (* [at] in the past *)
      assert (is_error (snapshot (const 14) ~at:(Time.sub (now ()) (sec 1.)) ~before:13));
    ;;

    TEST_UNIT = (* [at] in the future *)
      let o =
        observe (ok_exn (snapshot (const 14) ~at:(Time.add (now ()) (sec 1.)) ~before:13))
      in
      stabilize_ _here_;
      assert (value o = 13);
      stabilize_ _here_;
      advance_clock_by (sec 2.);
      assert (value o = 13);
      stabilize_ _here_;
      assert (value o = 14);
    ;;

    TEST_UNIT = (* [at] in the future, unobserved *)
      let x = Var.create_ _here_ 13 in
      let i =
        ok_exn (snapshot (Var.watch x) ~at:(Time.add (now ()) (sec 1.)) ~before:15)
      in
      stabilize_ _here_;
      Var.set x 17;
      advance_clock_by (sec 2.);
      stabilize_ _here_;
      Var.set x 19;
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 17);
    ;;

    TEST_UNIT = (* [advance_clock] past [at] prior to stabilization. *)
      let o =
        observe (ok_exn (snapshot (const 15) ~at:(Time.add (now ()) (sec 1.)) ~before:13))
      in
      advance_clock_by (sec 2.);
      stabilize_ _here_;
      assert (value o = 15);
    ;;

    TEST_UNIT = (* unobserved, [advance_clock] past [at] prior to stabilization. *)
      let x = Var.create_ _here_ 13 in
      let i =
        ok_exn (snapshot (Var.watch x) ~at:(Time.add (now ()) (sec 1.)) ~before:15)
      in
      advance_clock_by (sec 2.);
      stabilize_ _here_;
      Var.set x 17;
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 13);
    ;;

    TEST_UNIT = (* invalidated *)
      let t = ok_exn (snapshot invalid ~at:(Time.add (now ()) (sec 1.)) ~before:13) in
      let o = observe t in
      stabilize_ _here_;
      assert (value o = 13);
      advance_clock_by (sec 2.);
      stabilize_ _here_;
      assert (not (is_valid t));
      disallow_future_use o;
    ;;

    TEST_UNIT = (* [snapshot] nodes increment [num_nodes_became_necessary] *)
      let i1 = State.(num_nodes_became_necessary t) in
      let c = const () in
      for _i = 1 to 5 do
        ignore (ok_exn (snapshot c ~at:(Time.add (now ()) (sec 1.)) ~before:()) : _ t);
      done;
      advance_clock_by (sec 2.);
      let i2 = State.(num_nodes_became_necessary t) in
      <:test_result< int >> i2
        ~expect:(i1 + 6); (* the 5 [snapshot]s that became [freeze] plus the [const] *)
    ;;

    let step_function = step_function

    let relative_step_function ~init steps =
      let now = now () in
      step_function ~init (List.map steps ~f:(fun (after, a) ->
        (Time.add now (sec (Float.of_int after)), a)))
    ;;

    TEST = is_invalidated_on_bind_rhs (fun i -> step_function ~init:i [])

    TEST =
      is_invalidated_on_bind_rhs (fun i -> relative_step_function ~init:i [1, i + 1])
    ;;

    TEST_UNIT = (* no steps *)
      let i = step_function ~init:13 [] in
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 13);
    ;;

    TEST_UNIT = (* one step at a time *)
      let i =
        relative_step_function ~init:13
          [ 1, 14
          ; 2, 15
          ]
      in
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 13);
      advance_clock_by (sec 1.5);
      stabilize_ _here_;
      assert (value o = 14);
      advance_clock_by (sec 1.);
      stabilize_ _here_;
      assert (value o = 15);
    ;;

    TEST_UNIT = (* all steps in the past *)
      let i =
        relative_step_function ~init:13
          [ -2, 14
          ; -1, 15
          ]
      in
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 15);
    ;;

    TEST_UNIT = (* some steps in the past *)
      let i =
        relative_step_function ~init:13
          [ -1, 14
          ;  1, 15
          ]
      in
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 14);
      advance_clock_by (sec 1.5);
      stabilize_ _here_;
      assert (value o = 15);
    ;;

    TEST_UNIT = (* cross multiple steps in one stabilization cycle *)
      let i =
        relative_step_function ~init:13
          [ 1, 14
          ; 2, 15
          ]
      in
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 13);
      advance_clock_by (sec 1.5);
      advance_clock_by (sec 1.);
      stabilize_ _here_;
      assert (value o = 15);
    ;;

    TEST_UNIT = (* cross step in same stabilization as creation *)
      let i =
        relative_step_function ~init:13
          [ 1, 14
          ]
      in
      let o = observe i in
      advance_clock_by (sec 2.);
      stabilize_ _here_;
      assert (value o = 14);
    ;;

    TEST_UNIT = (* observe after step *)
      let i =
        relative_step_function ~init:13
          [ 1, 14
          ]
      in
      stabilize_ _here_;
      advance_clock_by (sec 1.5);
      stabilize_ _here_;
      let o = observe i in
      stabilize_ _here_;
      assert (value o = 14);
    ;;

    TEST_UNIT = (* advancing exactly to steps doesn't skip steps *)
      let base = now () in
      let curr = ref base in
      let steps = ref [] in
      for i = 1 to 20 do
        curr := Time.next_multiple ~base ~after:!curr ~interval:(sec 1.) ();
        steps := (!curr, i)::!steps
      done;
      let steps = List.rev !steps in
      let o = observe (step_function ~init:0 steps) in
      List.iter steps ~f:(fun (to_, i) ->
        advance_clock ~to_;
        stabilize_ _here_;
        <:test_result< int >> (value o) ~expect:(i-1);
      );
      disallow_future_use o;
    ;;

    TEST_UNIT = (* Equivalence between [step_function] and reimplementation with [at] *)
      let my_step_function ~init steps =
        let xs =
          Array.map (Array.of_list steps) ~f:(fun (time, x) ->
            map (at time) ~f:(function
              | Before -> None
              | After -> Some x))
        in
        array_fold xs ~init ~f:(fun acc x -> Option.value x ~default:acc)
      in
      let base = now () in
      let steps =
        List.map ~f:(fun (d, v) -> Time.add base (sec d), v)
          [ 1.0,     1
          ; 1.99999, 2 (* It is unspecified whether this alarm has fired when the time is
                          2. but this test relies on the two step_functions having the
                          same unspecified behaviour. *)
          ; 2.0,     3
          ; 3.00001, 4
          ; 4.0,     5
          ; 4.00001, 6
          ; 5.0,     6
          ; 6.0,     7
          ]
      in

      let o1 = observe (step_function ~init:0 steps) in
      let o2 = observe (my_step_function ~init:0 steps) in
      stabilize_ _here_;
      for i = 1 to 7 do
        advance_clock ~to_:(Time.add base (sec (Float.of_int i)));
        stabilize_ _here_;
        <:test_eq< int >> (value o1) (value o2)
      done;
      disallow_future_use o1;
      disallow_future_use o2;
    ;;

    TEST_UNIT = (* Advancing to a scheduled time shouldn't break things. *)
      let fut = Time.add (now ()) (sec 1.0) in
      let o1 = observe (at fut) in
      let o2 = observe (ok_exn (snapshot (const 1) ~at:fut ~before:0)) in
      advance_clock ~to_:fut;
      stabilize_ _here_;
      disallow_future_use o1;
      disallow_future_use o2;
    ;;

    TEST_UNIT = (* alarms get cleaned up for invalidated time-based incrementals *)
      List.iter
        [ (fun () -> after (sec 1.) >>| fun _ -> ())
        ; (fun () -> at_intervals (sec 1.))
        ; (fun () -> relative_step_function ~init:() [ 1, () ])
        ]
        ~f:(fun create_time_based_incremental ->
          let num_alarms = State.(timing_wheel_length t) in
          let x = Var.create_ _here_ 0 in
          let o =
            observe (bind (Var.watch x) (fun i ->
              if i >= 0
              then create_time_based_incremental ()
              else return ()))
          in
          stabilize_ _here_;
          for i = 1 to 10 do
            Var.set x i;
            stabilize_ _here_;
            <:test_result< int >> ~expect:(num_alarms + 1) State.(timing_wheel_length t);
          done;
          Var.set x (-1);
          stabilize_ _here_;
          <:test_result< int >> ~expect:num_alarms State.(timing_wheel_length t);
          disallow_future_use o);
    ;;

    module Observer = struct

      open Observer

      type nonrec 'a t = 'a t with sexp_of

      TEST =
        let string =
          observe (watch (Var.create 13))
          |> <:sexp_of< int t >>
          |> Sexp.to_string_hum
        in
        is_some (String.substr_index string
                   ~pattern:"Observer.value_exn called without stabilizing")
      ;;

      let invariant = invariant

      let observing = observing

      TEST_UNIT =
        let x = Var.create_ _here_ 0 in
        let o = observe (watch x) in
        assert (phys_same (observing o) (watch x));
      ;;

      let use_is_allowed = use_is_allowed

      TEST_UNIT =
        let o = observe (watch (Var.create_ _here_ 0)) in
        assert (use_is_allowed o);
        disallow_future_use o;
        assert (not (use_is_allowed o));
      ;;

      let disallow_future_use = disallow_future_use
      let value               = value
      let value_exn           = value_exn

      TEST_UNIT = (* calling [value] before stabilizing returns error. *)
        let x = Var.create_ _here_ 0 in
        let o = observe (watch x) in
        assert (is_error (value o));
        assert (does_raise (fun () -> value_exn o));
      ;;

      TEST_UNIT =
        (* calling [value] on a just-created observer of an already computed incremental
           before stabilizing returns error. *)
        let x = Var.create_ _here_ 13 in
        let o = observe (watch x) in
        stabilize_ _here_;
        disallow_future_use o;
        Var.set x 14;
        stabilize_ _here_;
        Var.set x 15;
        let o = observe (watch x) in
        assert (is_error (value o));
        assert (does_raise (fun () -> value_exn o));
      ;;

      TEST_UNIT = (* calling [value] after [disallow_future_use] returns error. *)
        let x = Var.create_ _here_ 0 in
        let o = observe (watch x) in
        stabilize_ _here_;
        disallow_future_use o;
        assert (is_error (value o));
        assert (does_raise (fun () -> value_exn o));
      ;;

      TEST_UNIT = (* [disallow_future_use] disables on-update handlers. *)
        let x = Var.create_ _here_ 13 in
        let o = observe (Var.watch x) in
        let r = ref 0 in
        Observer.on_update_exn o ~f:(fun _ -> incr r);
        stabilize_ _here_;
        assert (!r = 1);
        disallow_future_use o;
        Var.set x 14;
        stabilize_ _here_;
        assert (!r = 1);
      ;;

      TEST_UNIT = (* finalizers work *)
        Gc.full_major ();
        stabilize_ _here_;  (* clean up pre-existing finalizers *)
        let before = State.(num_active_observers t) in
        let x = Var.create_ _here_ 13 in
        let o = observe (Var.watch x) in
        assert (State.(num_active_observers t) = before + 1);
        stabilize_ _here_;
        assert (value_exn o = 13);
        Gc.full_major ();
        assert (State.(num_active_observers t) = before + 1);
        stabilize_ _here_;
        assert (State.(num_active_observers t) = before);
      ;;

      TEST_UNIT = (* finalizers don't disable on-update handlers *)
        let x = Var.create_ _here_ 13 in
        let o = observe (Var.watch x) in
        let r = ref 0 in
        Observer.on_update_exn o ~f:(fun _ -> incr r);
        stabilize_ _here_;
        assert (!r = 1);
        Gc.full_major ();
        Var.set x 14;
        stabilize_ _here_;
        assert (!r = 2);
      ;;

      TEST_UNIT = (* finalizers cause an [Unnecessary] update to be sent *)
        let x = Var.create 13 in
        let o = observe (watch x) in
        let push, check = on_update_queue () in
        on_update (watch x) ~f:push;
        stabilize_ _here_;
        check [ Necessary 13 ];
        Gc.keep_alive o;
        Gc.full_major ();
        stabilize_ _here_;
        check [ Unnecessary ];
      ;;


      TEST_UNIT = (* [disallow_future_use] and finalize in the same stabilization. *)
        let x = Var.create_ _here_ 1 in
        let o = observe (Var.watch x) in
        stabilize_ _here_;
        disallow_future_use o;
        Gc.full_major ();
        stabilize_ _here_;
      ;;

      TEST_UNIT = (* finalize after disallow_future_use *)
        let x = Var.create_ _here_ 1 in
        let o = observe (Var.watch x) in
        stabilize_ _here_;
        disallow_future_use o;
        stabilize_ _here_;
        (* This [full_major] + [stabilize] causes the finalizer for [o] to run and makes
           sure that it doesn't do anything wrong, given that [disallow_future_use o] has
           already been called. *)
        Gc.full_major ();
        stabilize_ _here_;
      ;;

      TEST_UNIT = (* after user resurrection of an observer, it is still disallowed *)
        let x = Var.create_ _here_ 13 in
        let o = observe (Var.watch x) in
        stabilize_ _here_;
        Gc.keep_alive o;
        let r = ref None in
        Gc.Expert.add_finalizer_exn o (fun o -> r := Some o);
        Gc.full_major ();
        stabilize_ _here_;
        let o = Option.value_exn !r in
        assert (not (use_is_allowed o));
      ;;

      TEST_UNIT = (* lots of observers on the same node isn't quadratic. *)
        (* We can't run this test with debugging, because it's too slow. *)
        if not debug then begin
          let t = const 13 in
          let observers = List.init 100_000 ~f:(fun _ -> observe t) in
          let cpu_used () =
            let module R = Unix.Resource_usage in
            let { R. utime; stime; _ } = R.get `Self in
            Time.Span.of_float (utime +. stime)
          in
          let before = cpu_used () in
          (* Don't use [stabilize_], which runs the invariant, which is too slow here. *)
          stabilize ();
          List.iter observers ~f:Observer.disallow_future_use;
          stabilize ();
          let consumed = Time.Span.(-) (cpu_used ()) before in
          if verbose then Debug.ams _here_ "consumed" consumed <:sexp_of< Time.Span.t >>;
          assert (Time.Span.(<) consumed (sec 1.));
        end
      ;;

      module Update = Update

      let on_update_exn = on_update_exn

      TEST_UNIT =
        let x = Var.create_ _here_ 13 in
        let parent = map (watch x) ~f:(fun x ->  x + 1) in
        let parent_o = observe parent in
        let num_calls = ref 0 in
        let r = ref 0 in
        on_update_exn parent_o ~f:(function
          | Initialized i | Changed (_, i) ->
            num_calls := !num_calls + 1;
            r := i
          | Invalidated -> assert false);
        stabilize_ _here_;
        assert (!num_calls = 1);
        Var.set x 15;
        stabilize_ _here_;
        assert (!num_calls = 2);
        assert (!r = 16);
        disallow_future_use parent_o;
        Var.set x 17;
        stabilize_ _here_;
        assert (!num_calls = 2);
        assert (!r = 16);
      ;;

      TEST_UNIT = (* [on_update_exn] of an invalid node, not during a stabilization *)
        let o = observe invalid in
        on_update_exn o ~f:(fun _ -> assert false);
        disallow_future_use o;
      ;;

      TEST_UNIT = (* [on_update_exn] of an invalid node *)
        let o = observe invalid in
        let is_ok = ref false in
        on_update_exn o ~f:(function
          | Invalidated -> is_ok := true
          | _ -> assert false);
        stabilize_ _here_;
        assert !is_ok;
      ;;

      TEST_UNIT = (* stabilizing with an on-update handler of a node that is invalidated *)
        let x = Var.create 0 in
        let r = ref None in
        let o1 = observe (bind (watch x) (fun i -> let t = const i in r := Some t; t)) in
        stabilize_ _here_;
        let o2 = observe (Option.value_exn !r) in
        let invalidated = ref false in
        Observer.on_update_exn o2 ~f:(function
          | Invalidated -> invalidated := true
          | _ -> ());
        stabilize_ _here_;
        assert (not !invalidated);
        Var.set x 1;
        stabilize_ _here_;
        assert !invalidated;
        disallow_future_use o1;
        disallow_future_use o2;
      ;;

      TEST_UNIT = (* [on_update_exn] of a disallowed observer *)
        let o = observe (const 5) in
        disallow_future_use o;
        assert (does_raise (fun () ->
          on_update_exn o ~f:(fun _ -> assert false)));
      ;;

      TEST_UNIT = (* [disallow_future_use] before first stabilization *)
        let o = observe (const 5) in
        disallow_future_use o;
        stabilize_ _here_;
        disallow_future_use o;
      ;;

      TEST_UNIT = (* [disallow_future_use] during an on-update handler *)
        let x = Var.create_ _here_ 13 in
        let o = observe (watch x) in
        on_update_exn o ~f:(fun _ -> disallow_future_use o);
        stabilize_ _here_;
        assert (is_error (value o));
      ;;

      TEST_UNIT = (* disallowing other on-update handlers in an on-update handler *)
        let x = Var.create_ _here_ 13 in
        let o = observe (watch x) in
        for _i = 1 to 2 do
          on_update_exn o ~f:(fun _ ->
            assert (use_is_allowed o);
            disallow_future_use o);
        done;
        stabilize_ _here_;
      ;;

      TEST_UNIT = (* disallowing other observers of the same node an on-update handler *)
        let x = Var.create_ _here_ 13 in
        let o1 = observe (watch x) in
        let o2 = observe (watch x) in
        let o3 = observe (watch x) in
        List.iter [ o1; o3 ] ~f:(fun o ->
          on_update_exn o ~f:(fun _ -> assert (use_is_allowed o)));
        on_update_exn o2 ~f:(fun _ ->
          disallow_future_use o1;
          disallow_future_use o3);
        stabilize_ _here_;
      ;;

      TEST_UNIT = (* disallowing observers of other nodes in an on-update handler *)
        let o () = observe (watch (Var.create_ _here_ 13)) in
        let o1 = o () in
        let o2 = o () in
        let o3 = o () in
        List.iter [ o1; o3 ] ~f:(fun o ->
          on_update_exn o ~f:(fun _ -> assert (use_is_allowed o)));
        on_update_exn o2 ~f:(fun _ ->
          disallow_future_use o1;
          disallow_future_use o3);
        stabilize_ _here_;
      ;;

      TEST_UNIT = (* adding an on-update-handler to an already stable node *)
        let x = watch (Var.create 13) in
        let o = observe x in
        stabilize_ _here_;
        let did_run = ref false in
        on_update_exn (observe x) ~f:(fun _ -> did_run := true);
        assert (not !did_run);
        stabilize_ _here_;
        assert !did_run;
        disallow_future_use o;
      ;;

      TEST_UNIT = (* adding an on-update handler after a change *)
        let x = Var.create 13 in
        let o = observe (watch x) in
        let push1, check1 = on_observer_update_queue () in
        Observer.on_update_exn o ~f:push1;
        stabilize_ _here_;
        check1 [ Initialized 13 ];
        Var.set x 14;
        stabilize_ _here_;
        check1 [ Changed (13, 14) ];
        let push2, check2 = on_observer_update_queue () in
        Observer.on_update_exn o ~f:push2;
        stabilize_ _here_;
        check2 [ Initialized 14 ];
        Var.set x 15;
        stabilize_ _here_;
        check1 [ Changed (14, 15) ];
        check2 [ Changed (14, 15) ];
      ;;

      TEST_UNIT = (* adding an on-update handler in an on-update handler. *)
        let x = Var.create 13 in
        let o = observe (watch x) in
        let did_run = ref false in
        on_update_exn o ~f:(fun _ ->
          on_update_exn (observe (watch x))
            ~f:(fun _ -> did_run := true));
        stabilize_ _here_;
        assert (not !did_run);
        Var.set x 14;
        stabilize_ _here_;
        assert !did_run;
        Gc.full_major ();
        stabilize_ _here_;
      ;;

      TEST_UNIT = (* adding an on-update-handler to an invalid node in an on-update
                     handler. *)
        let module I = Make () in
        let open I in
        let o = observe (watch (Var.create 13)) in
        let is_ok = ref false in
        Observer.on_update_exn o ~f:(fun _ ->
          Observer.on_update_exn (observe invalid)
            ~f:(function
              | Invalidated -> is_ok := true
              | _ -> assert false));
        stabilize_ _here_;
        assert (not !is_ok);
        stabilize_ _here_;
        assert !is_ok;
      ;;

      TEST_UNIT =
        (* on-update-handlers added during the firing of other on-update-handlers should
           not fire now but instead after the next stabilization *)
        List.iter [ const 1; invalid ]
          ~f:(fun node ->
            let o1 = observe (const 1) in
            let o2 = observe node in
            let ran = ref 0 in
            Observer.on_update_exn o1 ~f:(fun _ ->
              Observer.on_update_exn o2 ~f:(fun _ -> incr ran));
            Observer.on_update_exn o2 ~f:(fun _ -> ());
            assert (!ran = 0);
            stabilize_ _here_;
            assert (!ran = 0);
            stabilize_ _here_;
            assert (!ran = 1);
            stabilize_ _here_;
            assert (!ran = 1);
            disallow_future_use o1;
            disallow_future_use o2;
          )
      ;;

      TEST_UNIT = (* on-update handler set up during stabilization fires after the
                     stabilization *)
        let called = ref false in
        let unit = const () in
        let o_unit = observe unit in
        let o = observe (map unit ~f:(fun () ->
          on_update_exn o_unit ~f:(fun _ -> called := true)))
        in
        assert (not !called);
        stabilize_ _here_;
        assert (!called);
        disallow_future_use o;
        disallow_future_use o_unit;
      ;;

      TEST_UNIT = (* on-update handlers are initialized once *)
        let v = Var.create (const 0) in
        let i = Var.watch v in
        let o = observe i in
        let old_val_is_none_once () =
          let is_first_call = ref true in
          function
          | Observer.Update.Initialized _ -> assert !is_first_call; is_first_call := false;
          | Changed _     -> assert (not !is_first_call);
          | Invalidated   -> assert false
        in
        Observer.on_update_exn o ~f:(old_val_is_none_once ());
        stabilize ();
        Observer.on_update_exn o ~f:(old_val_is_none_once ());
        stabilize ()
      ;;

      TEST_UNIT = (* creating an observer during stabilization *)
        let x = Var.create 13 in
        let r = ref None in
        let o1 =
          observe (Var.watch x
                   >>| fun _ ->
                   let o2 = observe (Var.watch x) in
                   assert (use_is_allowed o2);
                   assert (is_error (value o2));
                   r := Some o2;
                   0)
        in
        stabilize_ _here_;
        let o2 = Option.value_exn !r in
        assert (use_is_allowed o2);
        assert (is_error (value o2));
        stabilize_ _here_;
        assert (value_exn o2 = 13);
        disallow_future_use o1;
        disallow_future_use o2;
        stabilize_ _here_;
        assert (is_error (value o2));
      ;;

      TEST_UNIT = (* creating an observer and adding on_update handler during
                     stabilization *)
        let v = Var.create 0 in
        let push, check = on_observer_update_queue () in
        let inner_obs = ref None in
        let o =
          observe (Var.watch v >>| fun i ->
                   let observer = observe (Var.watch v) in
                   inner_obs := Some observer;
                   on_update_exn observer ~f:push;
                   i)
        in
        check [];
        stabilize_ _here_;
        check [];
        stabilize_ _here_;
        check [ Initialized 0 ];
        disallow_future_use o;
        disallow_future_use (Option.value_exn !inner_obs);
      ;;

      TEST_UNIT = (* disallow_future_use during stabilization *)
        let x = Var.create 13 in
        let handler_ran = ref false in
        let o1 = observe (Var.watch x) in
        let o2 = observe (Var.watch x >>| fun i ->
                          on_update_exn o1 ~f:(fun _ -> handler_ran := true);
                          disallow_future_use o1;
                          assert (not (use_is_allowed o1));
                          i)
        in
        assert (use_is_allowed o1);
        assert (not !handler_ran);
        stabilize_ _here_;
        assert (not (use_is_allowed o1));
        assert (not !handler_ran);
        disallow_future_use o2;
      ;;

      TEST_UNIT = (* creating an observer and disallowing use during stabilization *)
        let x = Var.create 13 in
        let r = ref None in
        let o1 =
          observe (Var.watch x
                   >>| fun _ ->
                   let o2 = observe (Var.watch x) in
                   r := Some o2;
                   disallow_future_use o2;
                   0)
        in
        stabilize_ _here_;
        let o2 = Option.value_exn !r in
        assert (not (use_is_allowed o2));
        disallow_future_use o1;
        stabilize_ _here_;
      ;;

      TEST_UNIT = (* creating an observer and finalizing it during stabilization *)
        let x = Var.create 13 in
        let o =
          observe (Var.watch x
                   >>| fun _ ->
                   Fn.ignore (observe (Var.watch x) : _ Observer.t);
                   Gc.full_major ();
                   0)
        in
        stabilize_ _here_;
        stabilize_ _here_;
        disallow_future_use o;
      ;;
    end

    let on_update = on_update

    TEST_UNIT =
      let v = Var.create_ _here_ 13 in
      let push, check = on_update_queue () in
      let o = observe (watch v) in
      on_update (watch v) ~f:push;
      stabilize_ _here_;
      check [ Necessary 13 ];
      stabilize_ _here_;
      check [];
      Var.set v 14;
      stabilize_ _here_;
      check [ Changed (13, 14) ];
      disallow_future_use o;
      Var.set v 15;
      stabilize_ _here_;
      check [ Unnecessary ];
    ;;

    TEST_UNIT = (* on-change handlers of a node that changes but is not necessary
                   at the end of a stabilization *)
      let v = Var.create_ _here_ 0 in
      let n = Var.watch v in
      let push, check = on_update_queue () in
      on_update n ~f:push;
      let o = observe n in
      stabilize_ _here_;
      check [ Necessary 0 ];
      disallow_future_use o;
      Var.set v 1;
      let o = observe (freeze n) in
      stabilize_ _here_;
      check [ Unnecessary ];
      disallow_future_use o;
    ;;

    TEST_UNIT = (* value changing with different observers *)
      let v = Var.create_ _here_ 13 in
      let o = observe (watch v) in
      let push, check = on_update_queue () in
      on_update (watch v) ~f:push;
      stabilize_ _here_;
      check [ Necessary 13 ];
      disallow_future_use o;
      stabilize_ _here_;
      check [ Unnecessary ];
      Var.set v 14;
      let o = observe (watch v) in
      stabilize_ _here_;
      disallow_future_use o;
      check [ Necessary 14 ];
    ;;

    TEST_UNIT = (* call at next stabilization *)
      let v = Var.create_ _here_ 13 in
      let o = observe (Var.watch v) in
      stabilize_ _here_;
      let r = ref 0 in
      on_update (Var.watch v) ~f:(fun _ -> incr r);
      stabilize_ _here_;
      assert (!r = 1);
      disallow_future_use o;
    ;;

    TEST_UNIT = (* called at next stabilization with [Unnecessary] update *)
      let v = Var.create_ _here_ 13 in
      let o = observe (Var.watch v) in
      stabilize_ _here_;
      let push, check = on_update_queue () in
      on_update (watch v) ~f:push;
      disallow_future_use o;
      stabilize_ _here_;
      check [ Unnecessary ];
    ;;

    TEST_UNIT = (* transition from unnecessary to necessary and back *)
      let x = Var.create 13 in
      let push, check = on_update_queue () in
      on_update (watch x) ~f:push;
      stabilize_ _here_;
      check [ Unnecessary ];
      let o = observe (watch x) in
      stabilize_ _here_;
      check [ Necessary 13 ];
      Var.set x 14;
      stabilize_ _here_;
      check [ Changed (13, 14) ];
      disallow_future_use o;
      stabilize_ _here_;
      check [ Unnecessary ];
    ;;

    TEST_UNIT = (* an indirectly necessary node *)
      let x = Var.create_ _here_ 13 in
      let push, check = on_update_queue () in
      on_update (Var.watch x) ~f:push;
      let t = Var.watch x >>| fun i -> i + 1 in
      stabilize_ _here_;
      check [ Unnecessary ];
      let o = observe t in
      stabilize_ _here_;
      check [ Necessary 13 ];
      disallow_future_use o;
      stabilize_ _here_;
      check [ Unnecessary ];
      let o = observe t in
      stabilize_ _here_;
      check [ Necessary 13 ];
      disallow_future_use o;
      stabilize_ _here_;
      check [ Unnecessary ];
    ;;

    TEST_UNIT = (* [on_update] doesn't make a node necessary *)
      let v = Var.create_ _here_ 13 in
      let push, check = on_update_queue () in
      on_update (watch v) ~f:push;
      stabilize_ _here_;
      check [ Unnecessary ];
      Var.set v 14;
      stabilize_ _here_;
      check [];
      let o = observe (Var.watch v) in
      stabilize_ _here_;
      check [ Necessary 14 ];
      disallow_future_use o;
    ;;

    TEST_UNIT = (* invalid from the start *)
      let push, check = on_update_queue () in
      on_update invalid ~f:push;
      stabilize_ _here_;
      check [ Invalidated ];
    ;;

    TEST_UNIT = (* invalidation of an unnecessary node *)
      let v = Var.create_ _here_ 13 in
      let r = ref None in
      let o = observe (bind (watch v) (fun i -> r := Some (const i); return ())) in
      stabilize_ _here_;
      let i = Option.value_exn !r in
      let push, check = on_update_queue () in
      on_update i ~f:push;
      stabilize_ _here_;
      check [ Unnecessary ];
      Var.set v 14;
      stabilize_ _here_;
      check [ Invalidated ];
      disallow_future_use o;
    ;;

    TEST_UNIT = (* invalidation of a necessary node *)
      let v = Var.create_ _here_ 13 in
      let r = ref None in
      let o1 = observe (bind (watch v) (fun i -> r := Some (const i); return ())) in
      stabilize_ _here_;
      let i = Option.value_exn !r in
      let o2 = observe i in
      let push, check = on_update_queue () in
      on_update i ~f:push;
      stabilize_ _here_;
      check [ Necessary 13 ];
      Var.set v 14;
      stabilize_ _here_;
      check [ Invalidated ];
      disallow_future_use o1;
      disallow_future_use o2;
    ;;

    TEST_UNIT = (* invalidation of a necessary node after a change *)
      let v = Var.create_ _here_ 13 in
      let w = Var.create_ _here_ 14 in
      let r = ref None in
      let o1 =
        observe (bind (watch v) (fun _ ->
          r := Some (watch w >>| Fn.id);
          return ()))
      in
      stabilize_ _here_;
      let i = Option.value_exn !r in
      let o2 = observe i in
      let push, check = on_update_queue () in
      on_update i ~f:push;
      stabilize_ _here_;
      check [ Necessary 14 ];
      Var.set w 15;
      stabilize_ _here_;
      check [ Changed (14, 15) ];
      Var.set v 16;
      stabilize_ _here_;
      check [ Invalidated ];
      disallow_future_use o1;
      disallow_future_use o2;
    ;;

    TEST_UNIT = (* making a node necessary from an on-update handler *)
      let x = Var.create_ _here_ 13 in
      let y = Var.create_ _here_ 14 in
      let r = ref None in
      let push_x, check_x = on_update_queue () in
      on_update (watch x) ~f:push_x;
      let o = observe (watch y) in
      let push_o, check_o = on_observer_update_queue () in
      Observer.on_update_exn o ~f:(fun u ->
        push_o u;
        r := Some (observe (watch x)));
      stabilize_ _here_;
      check_x [ Unnecessary ];
      check_o [ Initialized 14 ];
      let ox = Option.value_exn !r in
      Var.set x 15;
      stabilize_ _here_;
      check_x [ Necessary 15 ];
      check_o [];
      disallow_future_use o;
      disallow_future_use ox;
    ;;

    TEST_UNIT = (* calling [advance_clock] in an on-update handler *)
      let i = after (sec 1.) in
      let o = observe i in
      let num_fires = ref 0 in
      on_update i ~f:(fun _ -> incr num_fires; advance_clock_by (sec 2.));
      assert (!num_fires = 0);
      stabilize_ _here_;
      assert (!num_fires = 1);
      stabilize_ _here_;
      assert (!num_fires = 2);
      disallow_future_use o;
    ;;

    module Cutoff = struct

      open Cutoff

      type nonrec 'a t = 'a t

      let sexp_of_t = sexp_of_t
      let invariant = invariant

      let create = create (* tested below *)

      let _ = create

      let of_compare = of_compare

      let should_cutoff = should_cutoff

      TEST_UNIT =
        let t = of_compare Int.compare in
        assert (should_cutoff t ~old_value:0 ~new_value:0);
        assert (not (should_cutoff t ~old_value:0 ~new_value:1));
      ;;

      let always = always

      TEST_UNIT =
        let x = Var.create_ _here_ 0 in
        set_cutoff (watch x) always;
        let r = ref 0 in
        let o = observe (watch x >>| fun _i -> incr r) in
        stabilize_ _here_;
        assert (!r = 1);
        List.iter
          [ 1, 1
          ; 0, 1
          ] ~f:(fun (v, expect) ->
            Var.set x v;
            stabilize_ _here_;
            assert (!r = expect));
        disallow_future_use o;
      ;;

      let never = never

      TEST_UNIT =
        let x = Var.create_ _here_ 0 in
        set_cutoff (watch x) never;
        let r = ref 0 in
        let o = observe (watch x >>| fun _i -> incr r) in
        stabilize_ _here_;
        assert (!r = 1);
        List.iter
          [ 1, 2
          ; 1, 3
          ; 1, 4
          ] ~f:(fun (v, expect) ->
            Var.set x v;
            stabilize_ _here_;
            assert (!r = expect));
        disallow_future_use o;
      ;;

      let phys_equal = phys_equal

      TEST_UNIT =
        let r1 = ref () in
        let r2 = ref () in
        let x = Var.create_ _here_ r1 in
        set_cutoff (watch x) phys_equal;
        let r = ref 0 in
        let o = observe (watch x >>| fun _i -> incr r) in
        stabilize_ _here_;
        assert (!r = 1);
        List.iter
          [ r1, 1
          ; r2, 2
          ; r2, 2
          ; r1, 3
          ] ~f:(fun (v, expect) ->
            Var.set x v;
            stabilize_ _here_;
            assert (!r = expect));
        disallow_future_use o;
      ;;

      let poly_equal = poly_equal

      TEST_UNIT =
        let r1a = ref 1 in
        let r1b = ref 1 in
        let r2 = ref 2 in
        let x = Var.create_ _here_ r1a in
        set_cutoff (watch x) poly_equal;
        let r = ref 0 in
        let o = observe (watch x >>| fun _i -> incr r) in
        stabilize_ _here_;
        assert (!r = 1);
        List.iter
          [ r1a, 1
          ; r1b, 1
          ; r2 , 2
          ; r1a, 3
          ] ~f:(fun (v, expect) ->
            Var.set x v;
            stabilize_ _here_;
            assert (!r = expect));
        disallow_future_use o;
      ;;

      let equal = equal

      TEST = equal never never
      TEST = not (equal never always)
    end

    let get_cutoff = get_cutoff
    let set_cutoff = set_cutoff

    TEST_UNIT =
      let i = Var.watch (Var.create_ _here_ 0) in
      assert (Cutoff.equal (get_cutoff i) Cutoff.phys_equal);
      set_cutoff i Cutoff.never;
      assert (Cutoff.equal (get_cutoff i) Cutoff.never);
    ;;

    TEST_UNIT =
      let a = Var.create_ _here_ 0 in
      let n = map ~f:Fn.id (watch a) in
      set_cutoff n (Cutoff.create
                      (fun ~old_value ~new_value -> abs (old_value - new_value) <= 1));
      let a' = observe n in
      stabilize_ _here_;
      assert (value a' = 0);
      List.iter
        [ 1, 0
        ; 2, 2
        ; 2, 2
        ] ~f:(fun (v, expect) ->
          Var.set a v;
          stabilize_ _here_;
          assert (value a' = expect));
    ;;

    module Scope = struct

      open Scope

      type nonrec t = t

      let top = top

      TEST_UNIT =
        let t = current () in
        assert (phys_equal t top);
      ;;

      let current = current
      let within  = within

      TEST_UNIT =
        let o = observe (within (current ()) ~f:(fun () -> const 13)) in
        stabilize_ _here_;
        assert (value o = 13);
      ;;

      TEST_UNIT = (* escaping a [bind] *)
        let s = current () in
        let r = ref None in
        let x = Var.create_ _here_ 13 in
        let o =
          observe (bind (watch x) (fun i ->
            r := Some (within s ~f:(fun () -> const i));
            return ()))
        in
        stabilize_ _here_;
        let o2 = observe (Option.value_exn !r) in
        stabilize_ _here_;
        assert (value o2 = 13);
        Var.set x 14;
        stabilize_ _here_;
        assert (value o2 = 13);
        disallow_future_use o;
        stabilize_ _here_;
        assert (value o2 = 13);
      ;;

      TEST_UNIT = (* returning to a [bind] *)
        let r = ref None in
        let x = Var.create_ _here_ 13 in
        let o1 =
          observe (bind (watch x) (fun _i ->
            r := Some (current ());
            return ()))
        in
        stabilize_ _here_;
        let s = Option.value_exn !r in
        let o2 = observe (within s ~f:(fun () -> const 13)) in
        stabilize_ _here_;
        assert (value o2 = 13);
        Var.set x 14;
        disallow_future_use o2;
        stabilize_ _here_;
        disallow_future_use o1;
      ;;
    end

    let lazy_from_fun = lazy_from_fun

    TEST_UNIT = (* laziness *)
      let r = ref 0 in
      let l = lazy_from_fun (fun () -> incr r) in
      assert (!r = 0);
      force l;
      assert (!r = 1);
      force l;
      assert (!r = 1);
    ;;

    TEST_UNIT = (* nodes created when forcing are in the right scope *)
      let l = lazy_from_fun (fun () -> const 13) in
      let x = Var.create_ _here_ 13 in
      let o = observe (bind (watch x) (fun _i -> force l)) in
      stabilize_ _here_;
      assert (value o = 13);
      Var.set x 14;
      stabilize_ _here_;
      assert (value o = 13);
    ;;

    let memoize_fun             = memoize_fun
    let memoize_fun_by_key      = memoize_fun_by_key
    let weak_memoize_fun        = weak_memoize_fun
    let weak_memoize_fun_by_key = weak_memoize_fun_by_key

    let test_memoize_fun memoize_fun =
      let x = Var.create_ _here_ 13 in
      let y = Var.create_ _here_ 14 in
      let z = Var.create_ _here_ 15 in
      let num_calls = ref 0 in
      let o =
        observe (
          (bind (bind (watch x)
                   (fun i1 ->
                      let f i2 =
                        incr num_calls;
                        map (watch y) ~f:(fun i3 -> i1 + i2 + i3)
                      in
                      return (unstage (memoize_fun Int.hashable f))))
             (fun f -> bind (watch z) f)))
      in
      stabilize_ _here_;
      <:test_eq< int >> (value o) 42;
      assert (!num_calls = 1);
      Var.set z 16;
      stabilize_ _here_;
      <:test_eq< int >> (value o) 43;
      assert (!num_calls = 2);
      Var.set z 17;
      stabilize_ _here_;
      assert (!num_calls = 3);
      <:test_eq< int >> (value o) 44;
      Var.set z 16;
      stabilize_ _here_;
      assert (!num_calls = 3);
      <:test_eq< int >> (value o) 43;
      Var.set y 20;
      stabilize_ _here_;
      assert (!num_calls = 3);
      <:test_eq< int >> (value o) 49;
      Var.set x 30;
      stabilize_ _here_;
      assert (!num_calls = 4);
      <:test_eq< int >> (value o) 66;
    ;;

    TEST_UNIT = test_memoize_fun memoize_fun

    TEST_UNIT = test_memoize_fun (fun hashable f -> memoize_fun_by_key hashable Fn.id f)

    TEST_UNIT =
      test_memoize_fun (fun hashable f ->
        let memo_f =
          unstage (weak_memoize_fun hashable (fun a -> Heap_block.create_exn (f a)))
        in
        stage (fun a -> Heap_block.value (memo_f a)))
    ;;

    TEST_UNIT =
      test_memoize_fun (fun hashable f ->
        let memo_f =
          unstage (weak_memoize_fun_by_key hashable Fn.id
                     (fun a -> Heap_block.create_exn (f a)))
        in
        stage (fun a -> Heap_block.value (memo_f a)))
    ;;

    TEST_UNIT = (* removal of unused data *)
      let num_calls = ref 0 in
      let f =
        unstage
          (weak_memoize_fun Int.hashable (function i ->
             incr num_calls;
             Heap_block.create_exn (ref i)))
      in
      let f i = Heap_block.value (f i) in
      let x0 = f 13 in
      let x0' = f 13 in
      let x1 = f 15 in
      assert (!num_calls = 2);
      assert (!x0 + !x0' + !x1 = 41);
      Gc.full_major ();
      assert (!num_calls = 2);
      let _x0 = f 13 in
      assert (!num_calls = 3);
      assert (phys_equal (f 15) x1);
      assert (!num_calls = 3);
      Gc.keep_alive x1;
    ;;

    TEST_UNIT = (* removing a parent is constant time *)
      (* We can't run this test with debugging, because it's too slow. *)
      if not debug then begin
        for e = 0 to 5 do
          let num_observers = Float.to_int (10. ** Float.of_int e) in
          let t = const 13 in
          let observers =
            List.init num_observers ~f:(fun _ -> observe (map t ~f:Fn.id))
          in
          let cpu_used () =
            let module R = Unix.Resource_usage in
            let { R. utime; stime; _ } = R.get `Self in
            Time.Span.of_float (utime +. stime)
          in
          let before = cpu_used () in
          (* Don't use [stabilize_], which runs the invariant, which is too slow here. *)
          stabilize ();
          List.iter observers ~f:disallow_future_use;
          stabilize ();
          let consumed = Time.Span.(-) (cpu_used ()) before in
          if verbose then Debug.ams _here_ "consumed" (num_observers, consumed)
                            <:sexp_of< int * Time.Span.t >>;
          assert (Time.Span.(<) consumed (sec 1.));
        done;
      end;
    ;;

    TEST_UNIT = (* Deleting a parent from a child in such a way that it is replaced by a
                   second parent, and the two parents have different child_indexes for
                   the child. *)
      let c1 = const 12 in
      let c2 = const 12 in
      let o1 = observe (map2 c1 c2 ~f:(+)) in (* c2 is child 1, o1 is parent 0 *)
      stabilize_ _here_;
      let o2 = observe (map c2 ~f:Fn.id) in (* c2 is child 0, o2 is parent 1 *)
      stabilize_ _here_;
      Observer.disallow_future_use o1; (* o2 is parent 0, so c2 is child 1 for that index *)
      stabilize_ _here_;
      Observer.disallow_future_use o2;
      stabilize_ _here_;
    ;;

  end :
    (* This signature constraint is here to remind us to add a unit test whenever the
       interface resulting from [Incremental.Make] changes. *)
    module type of Incremental.Make ()
  )
end

(* Situations that cause failures. *)

TEST_UNIT = (* stabilizing while stabilizing *)
  let module I = Make () in
  let open I in
  let o = observe (const () >>| fun () -> stabilize ()) in
  assert (does_raise stabilize);
  disallow_future_use o;
;;

TEST_UNIT = (* calling [set_max_height_allowed] while stabilizing *)
  let module I = Make () in
  let open I in
  let o = observe (const () >>| fun () -> State.(set_max_height_allowed t) 13) in
  assert (does_raise stabilize);
  disallow_future_use o;
;;

TEST_UNIT = (* creating a cycle *)
  let module I = Make () in
  let open I in
  let x = Var.create 1 in
  let r = ref (const 2) in
  let i = Var.watch x >>= fun x -> !r >>| fun y -> x + y in
  let o = observe i in
  stabilize_ _here_;
  assert (value o = 3);
  r := i;
  Var.set x 0;
  assert (does_raise stabilize);
;;

TEST_UNIT = (* trying to make a node necessary without its scope being necessary *)
  let module I = Make () in
  let open I in
  let r = ref None in
  let x = Var.create 13 in
  let o = observe (Var.watch x >>= fun i -> r := Some (const i); return ()) in
  stabilize_ _here_;
  let inner = Option.value_exn !r in
  disallow_future_use o;
  stabilize_ _here_; (* make [inner's] scope unnecessary *)
  let o = observe inner in
  assert (does_raise stabilize);
  disallow_future_use o;
;;

TEST_UNIT = (* stabilizing in an on-update handler *)
  let module I = Make () in
  let open I in
  let x = Var.create 13 in
  let o = observe (Var.watch x) in
  Observer.on_update_exn o ~f:(fun _ -> stabilize ());
  assert (does_raise stabilize);
  disallow_future_use o;
;;

TEST_UNIT = (* snapshot cycle *)
  let module I = Make () in
  let open I in
  let x = Var.create (const 14) in
  let s = ok_exn (snapshot (join (watch x)) ~at:(now ()) ~before:13) in
  advance_clock_by (sec 1.);
  Var.set x s;
  assert (does_raise stabilize);
;;

TEST_UNIT = (* snapshot cycle in the future *)
  let module I = Make () in
  let open I in
  let r = ref None in
  let value_at = bind (const ()) (fun () -> Option.value_exn !r) in
  let s = ok_exn (snapshot value_at ~at:(Time.add (now ()) (sec 1.)) ~before:13) in
  r := Some s;
  let o1 = observe value_at in
  let o2 = observe s in
  stabilize_ _here_;
  (* [advance_clock] should raise because the snapshot's [value_at] depends on the
     snapshot itself. *)
  assert (does_raise (fun () -> advance_clock ~to_:(Time.add (now ()) (sec 2.))));
  Gc.keep_alive (o1, o2);
;;


TEST_UNIT =
  let module I = Incremental.Make () in
  let open I in
  let v = Var.create (const 0) in
  let w = Var.create (const 0) in
  let a = join (Var.watch v) in
  let b = join (Var.watch w) in
  let os = observe a, observe b in
  assert (does_raise (fun () ->
    for _i=1 to 200 do
      Var.set w a;
      stabilize ();
      Var.set w (const 0);
      stabilize ();
      Var.set v b;
      stabilize ();
      Var.set v (const 0);
      stabilize ();
    done));
  Gc.keep_alive os;
;;

TEST_UNIT =
  let module I = Make () in
  let open I in
  let v = Var.create (const 0) in
  let w = Var.create (const 0) in
  let a = join (Var.watch v) in
  let b = join (Var.watch w) in
  let o = observe (map2 ~f:(+) a b) in
  (* [b] depends on [a] *)
  Var.set w a;
  Var.set v (const 2);
  stabilize ();
  assert (Observer.value_exn o = 4);
  (* [a] depends on [b] *)
  Var.set w (const 3);
  Var.set v b;
  assert (does_raise stabilize);
;;

(* Same as previous test, except with the [Var.set]s in the reverse order. *)
TEST_UNIT =
  let module I = Incremental.Make () in
  let open I in
  List.iter [join; fun x -> (x >>= fun x -> x)] ~f:(fun join ->
    let v = Var.create (const 0) in
    let w = Var.create (const 0) in
    let a = join (Var.watch v) in
    let b = join (Var.watch w) in
    let o = observe (map2 ~f:(+) a b) in
    stabilize ();
    assert (Observer.value_exn o = 0);
    (* [b] depends on [a], doing [Var.set]s in other order. *)
    Var.set v (const 2);
    Var.set w a;
    stabilize ();
    assert (Observer.value_exn o = 4);
    (* [a] depends on [b], doing [Var.set]s in other order. *)
    Var.set v b;
    Var.set w (const 3);
    stabilize ();
    assert (Observer.value_exn o = 6);
  );
;;

(* Demonstrates the cycle that isn't created in the above two tests. *)
TEST_UNIT =
  let module I = Incremental.Make () in
  let open I in
  let v = Var.create (const 0) in
  let w = Var.create (const 0) in
  let a = join (Var.watch v) in
  let b = join (Var.watch w) in
  let o = observe (map2 ~f:(+) a b) in
  Var.set v b;
  Var.set w a;
  assert (does_raise stabilize);
  Gc.keep_alive o;
;;

TEST_UNIT =
  let module I = Incremental.Make () in
  let open I in
  let v = Var.create true in
  let p = Var.watch v in
  let a = ref (const 0) in
  let b = ref (const 0) in
  a := p >>= (fun p -> if p then const 2 else !b);
  b := p >>= (fun p -> if p then !a else const 3);
  let o = observe (map2 ~f:(+) !a !b) in
  stabilize ();
  assert (Observer.value_exn o = 4);
  Var.set v false;
  assert (does_raise stabilize);
  (* assert (Observer.value_exn o = 6);
   * Var.set v true;
   * stabilize ();
   * assert (Observer.value_exn o = 4); *)
;;

TEST_UNIT =
  (* [at_intervals] doesn't try to add alarms before the current time, even when
     floating-point imprecision causes:

     {[
       let i = Timing_wheel.now_interval_num timing_wheel in
       assert (Timing_wheel.interval_num timing_wheel
                 (Timing_wheel.interval_num_start timing_wheel i)
               = i - 1);
     ]}
  *)
  let module I =
    Incremental.Make_with_timing_wheel_config (struct
      let config =
        Timing_wheel.Config.create
          ~alarm_precision:(sec 0.01)
          ~level_bits:(Timing_wheel.Level_bits.create_exn
                         [ 11; 10; 10; 10; 10; 10 ])
          ()
      let start = Time.of_string "2014-01-09 00:00:00.000000-05:00"
    end)()
  in
  let open I in
  advance_clock ~to_:(Time.of_string "2014-01-09 09:35:05.030000-05:00");
  let t = at_intervals (sec 1.) in
  let o = observe t in
  stabilize ();
  (* Here, we advance to a time that has the bad property mentioned above.  A previously
     buggy implementation of Incremental raised at this point because it tried to add the
     next alarm for the [at_intervals] in the past. *)
  advance_clock ~to_:(Time.of_string "2014-01-09 09:35:05.040000-05:00");
  stabilize ();
  Observer.disallow_future_use o;
;;