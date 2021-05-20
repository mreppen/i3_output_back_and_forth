(lang dune 2.7)
(generate_opam_files true)

(name i3_output_back_and_forth)
(source (github mreppen/i3_output_back_and_forth))

(package
  (name i3_output_back_and_forth)
  (synopsis "Extra support for back_and_forth switching with multiple outputs")
  (depends base (i3ipc (>= 0.4))))
