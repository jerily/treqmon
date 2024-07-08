# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package ifneeded treqmon 1.0.0 [list source [file join $dir treqmon.tcl]]

package ifneeded treqmon::worker 1.0.0 [list source [file join $dir worker.tcl]]
package ifneeded treqmon::common 1.0.0 [list source [file join $dir common.tcl]]

package ifneeded treqmon::output::console 1.0.0 [list source [file join $dir output_console.tcl]]
package ifneeded treqmon::output::file 1.0.0 [list source [file join $dir output_file.tcl]]
