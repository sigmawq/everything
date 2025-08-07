package profiler 
 
import "core:fmt"
import "core:strings"
import "core:math/rand"
import "core:time"

ENABLE_PROFILING :: true
ENABLE_FULL_PROFILING_INFO :: true
 
@(require_results)
_rdtsc :: #force_inline proc "c" () -> u64 {
	return rdtsc()
}
 
@(require_results)
__rdtscp :: #force_inline proc "c" (aux: ^u32) -> u64 {
	return rdtscp(aux)
}
 
@(private, default_calling_convention="c")
foreign _ {
	@(link_name="llvm.x86.rdtsc")
	rdtsc  :: proc() -> u64 ---
	@(link_name="llvm.x86.rdtscp")
	rdtscp :: proc(aux: rawptr) -> u64 ---
}
 
Profiler_Block :: struct {
    // Local block
    start: u64,
 
    parent: ^Profiler_Block,
 
    // Global block
    total_time_exclusive: u64,
    total_time_inclusive: u64,
    total_time_children: u64,
 
    total_operations: u64,
    total_bytes: u64,
    calls: u64,
 
    bytes: int,
}
cycles_per_second: u64
 
initialize_profiling :: proc() {
    WAIT :: 20
 
    acc: time.Duration
    start_cycles := _rdtsc()
    end_cycles := _rdtsc()
    start_time := time.now()
    end_time := time.now()
    for time.duration_milliseconds(time.diff(start_time, end_time)) < WAIT {
        end_time = time.now()
        end_cycles = _rdtsc()
    }
 
    diff := time.duration_milliseconds(time.diff(start_time, end_time))
    cycles_per_second = u64(f64(end_cycles - start_cycles) * (1000.0/diff))
 
    fmt.printf("Cycles per second: %v\n", cycles_per_second)    
}

current_profiler_block: ^Profiler_Block
current_profiler_blocks: ^[Profiler_Block_Id.LAST_PLUS_ONE]Profiler_Block

begin_profile_block :: proc(id: Profiler_Block_Id, #any_int operations: u64 = 0, #any_int bytes: u64 = 0) {
    when ENABLE_PROFILING && ENABLE_FULL_PROFILING_INFO {
        block := &current_profiler_blocks[id]
        block.start = _rdtsc()
        block.total_operations += operations
        block.total_bytes += bytes
        block.calls += 1
     
        if current_profiler_block != nil {
            block.parent = current_profiler_block
        }
     
        current_profiler_block = block
    }
}
 
end_profile_block :: proc() {
    when ENABLE_PROFILING && ENABLE_FULL_PROFILING_INFO {
        diff := _rdtsc() - current_profiler_block.start 
 
        current_profiler_block.total_time_exclusive += diff - current_profiler_block.total_time_children
        current_profiler_block.total_time_inclusive += diff

        if current_profiler_block.parent != nil {
            current_profiler_block.parent.total_time_children += diff
            current_profiler_block = current_profiler_block.parent
        } else {
            current_profiler_block = nil
        }    
    }
}

Saved_Profiling :: struct {
    blocks: ^[Profiler_Block_Id.LAST_PLUS_ONE]Profiler_Block,
    current_block: ^Profiler_Block
}

push_blocks :: proc(new_blocks: ^[Profiler_Block_Id.LAST_PLUS_ONE]Profiler_Block) -> Saved_Profiling {
    saved := Saved_Profiling {
        blocks = current_profiler_blocks,
        current_block = current_profiler_block,
    }

    current_profiler_blocks = new_blocks
    current_profiler_block = nil

    return saved
}

pop_blocks :: proc(saved: Saved_Profiling) {
    current_profiler_blocks = saved.blocks
    current_profiler_block = saved.current_block
}
 
profiler_output :: proc() {
    fmt.println("===========================================================")
    
    total_time: u64 = 0
    for i := 0; i < cast(int)Profiler_Block_Id.LAST_PLUS_ONE; i += 1 {
        block := &current_profiler_blocks[i]
    
        total_time += block.total_time_exclusive
    }
    
    ms := ( f64(total_time) / f64(cycles_per_second) ) * 1000
    fmt.printf("Total time is %v cycles, %v ms\n", total_time, ms)
    
    do_crap :: proc(block: ^Profiler_Block, id: Profiler_Block_Id, total_time: u64, indent: int) {
        for i in 0..<indent do fmt.printf("    ")
 
        percent_of_parent: f64 = 100
        
        parent := block.parent
        if parent != nil && !profiler_is_block_freestanding(id)  {
            percent_of_parent = ( f64(block.total_time_inclusive) / f64(parent.total_time_inclusive)) * 100
        } else {
            percent_of_parent = ( f64(block.total_time_exclusive) / f64(total_time) ) * 100
        }
        
        percent_of_total := ( f64(block.total_time_exclusive) / f64(total_time) ) * 100
        
        inclusive_time := f64(block.total_time_inclusive)/f64(cycles_per_second)
        inclusive_time_units := "s"
        if inclusive_time >= 0.001 && inclusive_time < 1 {
        	inclusive_time *= 1000
        	inclusive_time_units = "ms"
        } else if inclusive_time < 0.001 {
        	inclusive_time *= 1000000
        	inclusive_time_units = "us"
        }
        
        exclusive_time := f64(block.total_time_exclusive)/f64(cycles_per_second)
        exclusive_time_units := "s"
        if exclusive_time >= 0.001 && exclusive_time < 1 {
        	exclusive_time *= 1000
        	exclusive_time_units = "ms"
        } else if exclusive_time < 0.001 {
        	exclusive_time *= 1000000
        	exclusive_time_units = "us"
        }

        fmt.printf("%v[%v]: %v(%.3f%v/%.3f%%) (w/o children: %v, %.3f%v/%.3f%%) |", id, block.calls,
        	block.total_time_inclusive,
            inclusive_time,
            inclusive_time_units,
            percent_of_total,
        
            block.total_time_exclusive,
            exclusive_time,
            exclusive_time_units,
            percent_of_parent)
 
        if block.total_operations > 0 {
            fmt.printf(" %.3f cycles/op, (%v ops) |", f64(block.total_time_exclusive) / f64(block.total_operations), block.total_operations)
        }
 
        if block.total_bytes > 0 {
            ratio := f64(cycles_per_second) / f64(block.total_time_inclusive)
            bytes_per_second := f64(block.total_bytes) * ratio
            fmt.printf(" %v MB/S |", bytes_per_second / 1024 / 1024)
        }
 
        fmt.printf("\n")
    }
 
    dive :: proc(block: ^Profiler_Block, total_time: u64, indent: int) {
        for j := 0; j < cast(int)Profiler_Block_Id.LAST_PLUS_ONE; j += 1 {
            child_block := &current_profiler_blocks[j]
 
            if child_block.parent == block && !profiler_is_block_freestanding(auto_cast j) {
                do_crap(block = child_block, id = auto_cast j, total_time = total_time,  indent = indent+1)
 
                dive(block = child_block, total_time = total_time, indent = indent+1)
            }
        }    
    }
 
    for i := 0; i < cast(int)Profiler_Block_Id.LAST_PLUS_ONE; i += 1 {
        block := &current_profiler_blocks[i]
 
        block_name := fmt.tprintf("%v", cast(Profiler_Block_Id)i)
        if (block.parent != nil) {
            if !profiler_is_block_freestanding(cast(Profiler_Block_Id)i) do continue
        } 
        
        if block.total_time_inclusive == 0 do continue
 
        do_crap(block = block, id = Profiler_Block_Id(i), total_time = total_time, indent = 0)
        dive(block = block, total_time = total_time, indent = 0)
    }
}

reset_profiling :: proc() {
	current_profiler_blocks^ = {}
}

profiler_is_block_freestanding :: proc(id: Profiler_Block_Id) -> bool {
    name := fmt.tprintf("%v", id)
    return strings.has_prefix(name, "FS_")
}
 
Profiler_Block_Id :: enum {
	LAST_PLUS_ONE,
}