open Base
open I3ipc.Reply
module Event = I3ipc.Event

module Output = struct
  type t = string
  [@@deriving show]
  let equal = String.equal
end

module Workspace = struct
  type t = string
  [@@deriving show]
  let equal = String.equal
end

module Output_workspace_map = struct
  type t = ( Output.t * Workspace.t ) list
  [@@deriving show]
  let empty : t = []
  let get t out =
    List.Assoc.find t out ~equal:Output.equal
  let add t out ws =
    List.Assoc.add t out ws ~equal:Output.equal
end

module State = struct
  module Out_ws_map = Output_workspace_map
  type t =
    { restore : bool
    ; latest_out : Output.t
    ; latest_ws : Workspace.t
    ; alt_ws : Workspace.t
    ; latest_out_ws_map : Out_ws_map.t
    ; alt_out_ws_map : Out_ws_map.t }
  [@@deriving show]

  let update prev cur_out cur_ws =
    let new_restore, new_alt_map =
      match Out_ws_map.get prev.latest_out_ws_map cur_out with
      | None -> prev.restore, prev.alt_out_ws_map
      | Some cur_out_prev_ws ->
        let cur_out_ws_change = not (Workspace.equal cur_out_prev_ws cur_ws) in
        let out_change = not (Output.equal cur_out prev.latest_out) in

        let new_restore = cur_out_ws_change && out_change in
        let new_alt_map =
          if cur_out_ws_change
          then Out_ws_map.add prev.alt_out_ws_map cur_out cur_out_prev_ws
          else prev.alt_out_ws_map
        in
        new_restore, new_alt_map
    in

    let new_state =
      { restore = new_restore
      ; latest_out = cur_out
      ; latest_ws = cur_ws
      ; alt_ws = prev.latest_ws
      ; latest_out_ws_map = Out_ws_map.add prev.latest_out_ws_map cur_out cur_ws
      ; alt_out_ws_map = new_alt_map }
    in
    new_state

  let init = 
    { restore = false
    ; latest_out = ""
    ; latest_ws = ""
    ; alt_ws = ""
    ; latest_out_ws_map = Out_ws_map.empty
    ; alt_out_ws_map = Out_ws_map.empty }

  let current_out_alt_ws state = Out_ws_map.get state.alt_out_ws_map state.latest_out
  let get_alt_ws state = state.alt_ws
  let get_restore state = state.restore
end


let focused_output_id conn =
  let%lwt root = I3ipc.get_tree conn in
  List.hd_exn root.focus |> Lwt.return

let workspace_change conn (ws_event : Event.workspace_event_info) prev =
  match ws_event.change with
  | Event.Focus ->
    Option.value_map ws_event.current ~default:Lwt.return_none ~f:(fun cur_node ->
      let cur_ws = Option.value_exn cur_node.name in
      let%lwt cur_out = focused_output_id conn in
      Lwt.return_some (State.update prev cur_out cur_ws))
  | _ -> Lwt.return_none

let back_forth_on_output conn state_ref _signal =
  let output_prev_ws = State.current_out_alt_ws !state_ref in
  match output_prev_ws with None -> ()
  | Some output_prev_ws ->
    I3ipc.command conn (Printf.sprintf {|workspace "%s"|} output_prev_ws)
    |> Lwt.ignore_result

let back_forth_with_restore conn state_ref lock_ref _signal =
    let restore = State.get_restore !state_ref in
    let alt = State.get_alt_ws !state_ref in
    let ws_if_restore = State.current_out_alt_ws !state_ref in
    (let%lwt () =
      match restore, ws_if_restore with
      | true, Some ws_to_restore ->
        let%lwt _ = I3ipc.command conn (Printf.sprintf {|workspace "%s""|} ws_to_restore) in
        while%lwt not !lock_ref do Lwt_main.yield () done
      | _ -> Lwt.return_unit
    in
    I3ipc.command conn (Printf.sprintf {|workspace "%s"|} alt))
    |> Lwt.ignore_result

let main =
  let lock_ref = ref false in
  let state_ref = ref State.init in
  let%lwt conn = I3ipc.connect () in
  let%lwt handler_conn = I3ipc.connect () in
  Lwt_unix.on_signal Caml.Sys.sigusr1 (back_forth_on_output conn state_ref) |> ignore;
  Lwt_unix.on_signal Caml.Sys.sigusr2 (back_forth_with_restore conn state_ref lock_ref) |> ignore;
  let%lwt _ = I3ipc.subscribe conn [ I3ipc.Workspace ] in
  while%lwt true do
    match%lwt I3ipc.next_event conn with
    | Workspace ws_event ->
      let%lwt () = while%lwt !lock_ref do Lwt_main.yield () done in
      lock_ref := true;
      let%lwt new_state = workspace_change handler_conn ws_event !state_ref in
      Option.iter new_state ~f:(fun s -> state_ref := s);
      lock_ref := false;
      Lwt.return_unit
    | _ -> Lwt.return_unit
  done

let () = Lwt_main.run main
