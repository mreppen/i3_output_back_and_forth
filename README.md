# i3_output_back_and_forth

Extends the multi-monitor use of `back_and_forth` workspace switching of i3/Sway in the following two ways:
 1. Switch back and forth separately for each output, i.e., switch to the last used workspace on the current monitor.
 2. Restore the previously focused workspaces on back and forth, otherwise normal.  See description below.

Otherwise behaves like the built in `workspace back_and_forth`.

Only tested on Sway, but expected to work on i3.

## Description

 1. Consider a setup with workspaces 1 and 2 on output A and workspaces 3 and 4 on output B.  This feature would toggle between either 1 and 2 or 3 and 4 depending on which output is focused.
 2. Consider a setup with workspaces 1 and 2 on output A and workspace 3 on output B, with 3 focused and 1 visible:
    ```
    _1_  2  ||  *3*
    ```
    After switching with `workspace 2`, 1 is hidden:
    ```
     1  *2* ||  _3_
    ```
    The built in `back_and_forth` leads to
    ```
     1  _2_ ||  *3*
    ```
    whereas this feature reactivates 1, thus restoring the original view:
    ```
    _1_  2  ||  *3*
    ```

## Installation
I can provide binaries on request.

Install `ocaml` and `opam`.

If opam is not already initialized: `opam init`

Then run
```
opam pin i3_output_back_and_forth https://github.com/mreppen/i3_output_back_and_forth.git
opam install i3_output_back_and_forth
```

## Usage
Run this program at i3/Sway startup:
```
exec --no-startup-id "/path/to/i3_output_back_and_forth"
```

The switching in 1. or 2. is activated by sending a SIGUSR1 or SIGUSR2 to this program:
```
pkill -SIGUSR1 -x -f '[^ ]*i3_output_back_and_forth'
```
Note that this assumes that there is no space in the path.

This can be bound, e.g.,
```
bindsym $mod+Tab exec pkill -SIGUSR1 -x -f '[^ ]*i3_output_back_and_forth'
# 49=` on my system
bindcode $mod+49 exec pkill -SIGUSR2 -x -f '[^ ]*i3_output_back_and_forth'
```

## "Issues"

 - If no workspace has been changed since this application started, it opens an empty workspace when triggered.
 - Potentially unexpected behavior if triggered right after enabling/disabling outputs.  If so, it should fix itself after changing workspaces.

## See also

 - [i3-new-split-long](https://github.com/mreppen/i3-new-split-long): on new window, splits the current container in the dimension in which it is largest.
