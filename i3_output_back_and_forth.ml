open Base
open I3ipc.Reply
module Event = I3ipc.Event

module Output = struct
  type t = string
  let equal = String.equal
end

module Workspace = struct
  type t = string
  let equal = String.equal
end

let restore = ref false
let latest_out = ref ""
let latest_ws = ref ""
let alt_ws = ref ""
let latest_out_ws_map = (ref [], Output.equal)
let alt_out_ws_map = (ref [], Output.equal)

let get_map (map, equal) out =
  List.Assoc.find !map out ~equal

let set_map_ (map, equal) out ws =
  map := List.Assoc.add !map out ws ~equal

let focused_output_id conn =
  let%lwt root = I3ipc.get_tree conn in
  List.hd_exn root.focus |> Lwt.return

let workspace_change conn (ws_event : Event.workspace_event_info) =
  match ws_event.change with
  | Event.Focus ->
    Option.value_map ws_event.current ~default:Lwt.return_unit ~f:(fun cur_node ->
      let cur_ws = Option.value_exn cur_node.name in

      let%lwt cur_out = focused_output_id conn in

      (match get_map latest_out_ws_map cur_out with
      | None -> ()
      | Some cur_out_prev_ws ->
        let cur_out_ws_change = not (Workspace.equal cur_out_prev_ws cur_ws) in
        let out_change = not (Output.equal cur_out !latest_out) in

        restore := cur_out_ws_change && out_change;
        if cur_out_ws_change
        then set_map_ alt_out_ws_map cur_out cur_out_prev_ws
      );

      set_map_ latest_out_ws_map cur_out cur_ws;
      latest_out := cur_out;
      alt_ws := !latest_ws;
      latest_ws := cur_ws;
      Lwt.return_unit)
  | _ -> Lwt.return_unit
  

let main =
  let lock = ref false in
  let%lwt conn = I3ipc.connect () in
  let%lwt handler_conn = I3ipc.connect () in
  Lwt_unix.on_signal Caml.Sys.sigusr1 (fun _ ->
    let output_prev_ws = get_map alt_out_ws_map !latest_out in
    match output_prev_ws with None -> ()
    | Some output_prev_ws ->
      I3ipc.command conn (Printf.sprintf {|workspace "%s"|} output_prev_ws)
      |> Lwt.ignore_result)
  |> ignore;
  Lwt_unix.on_signal Caml.Sys.sigusr2 (fun _ ->
    let alt = !alt_ws in
    let ws_if_restore = get_map alt_out_ws_map !latest_out in
    (let%lwt () =
      match !restore, ws_if_restore with
      | true, Some ws_to_restore ->
        let%lwt _ = I3ipc.command conn (Printf.sprintf {|workspace "%s""|} ws_to_restore) in
        while%lwt not !lock do Lwt_main.yield () done
      | _ -> Lwt.return_unit
    in
    I3ipc.command conn (Printf.sprintf {|workspace "%s"|} alt))
    |> Lwt.ignore_result)
  |> ignore;
  let%lwt _ = I3ipc.subscribe conn [ I3ipc.Workspace ] in
  while%lwt true do
    match%lwt I3ipc.next_event conn with
    | Workspace ws_event ->
      let%lwt () = while%lwt !lock do Lwt_main.yield () done in
      lock := true;
      let%lwt _ = workspace_change handler_conn ws_event in
      lock := false;
      Lwt.return_unit
    | _ -> Lwt.return_unit
  done

let () = Lwt_main.run main
