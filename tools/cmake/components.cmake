# Search 'component_dirs' for components and return them
# as a list of names in 'component_names' and a list of full paths in
# 'component_paths'
#
# component_paths contains only unique component names. Directories
# earlier in the component_dirs list take precedence.
function(components_find_all component_dirs filter_names component_paths component_names)
  # component_dirs entries can be files or lists of files
  set(paths "")
  set(names "")

  # start by expanding the component_dirs list with all subdirectories
  foreach(dir ${component_dirs})
    # Iterate any subdirectories for values
    file(GLOB subdirs LIST_DIRECTORIES true "${dir}/*")
    foreach(subdir ${subdirs})
      set(component_dirs "${component_dirs};${subdir}")
    endforeach()
  endforeach()

  # Look for a component in each component_dirs entry
  foreach(dir ${component_dirs})
    file(GLOB component "${dir}/CMakeLists.txt")
    if(component)
      get_filename_component(component "${component}" DIRECTORY)
      get_filename_component(name "${component}" NAME)
      if(NOT filter_names OR (name IN_LIST filter_names))
        if(NOT name IN_LIST names)
          set(names "${names};${name}")
          set(paths "${paths};${component}")
        endif()
      endif()

    else()  # no CMakeLists.txt file
      # test for legacy component.mk and warn
      file(GLOB legacy_component "${dir}/component.mk")
      if(legacy_component)
        get_filename_component(legacy_component "${legacy_component}" DIRECTORY)
        message(WARNING "Component ${legacy_component} contains old-style component.mk but no CMakeLists.txt. Component will be skipped.")
      endif()
    endif(component)

  endforeach(dir ${component_dirs})

  set(${component_paths} ${paths} PARENT_SCOPE)
  set(${component_names} ${names} PARENT_SCOPE)
endfunction(components_find_all)


# Add a component to the build, using the COMPONENT variables defined
# in the parent
#
function(register_component)
  get_filename_component(component_dir ${CMAKE_CURRENT_LIST_FILE} DIRECTORY)
  get_filename_component(component ${component_dir} NAME)

  if(NOT COMPONENT_SRCDIRS)
    set(COMPONENT_SRCDIRS ".")
  endif()
  spaces2list(COMPONENT_SRCDIRS)

  if(NOT COMPONENT_ADD_INCLUDEDIRS)
    set(COMPONENT_ADD_INCLUDEDIRS "include")
  endif()
  spaces2list(COMPONENT_ADD_INCLUDEDIRS)

  # if not explicit, build COMPONENT_SRCS by globbing in COMPONENT_SRCDIRS
  if(NOT COMPONENT_SRCS)
    foreach(dir ${COMPONENT_SRCDIRS})
      get_filename_component(dir ${dir} ABSOLUTE BASE_DIR ${component_dir})
      file(GLOB matches "${dir}/*.[c|S]" "${dir}/*.cpp")
      if(matches)
        list(SORT matches)
        set(COMPONENT_SRCS "${COMPONENT_SRCS};${matches}")
      endif(matches)
    endforeach()
  endif()

  # add public includes from other components when building this component
  if(COMPONENT_SRCS OR embed_binaries)
    add_library(${component} STATIC ${COMPONENT_SRCS})
    set(include_type PUBLIC)
  else()
    add_library(${component} INTERFACE) # header-only component
    set(include_type INTERFACE)
  endif()

  # binaries to embed directly in library
  spaces2list(COMPONENT_EMBED_FILES)
  spaces2list(COMPONENT_EMBED_TXTFILES)
  foreach(embed_data ${COMPONENT_EMBED_FILES} ${COMPONENT_EMBED_TXTFILES})
    if (embed_data IN_LIST COMPONENT_EMBED_TXTFILES)
      set(embed_type "TEXT")
    else()
      set(embed_type "BINARY")
    endif()
    target_add_binary_data("${component}" "${embed_data}" "${embed_type}")
  endforeach()

  # add public includes
  foreach(include_dir ${COMPONENT_ADD_INCLUDEDIRS})
    get_filename_component(include_dir ${include_dir} ABSOLUTE BASE_DIR ${component_dir})
    target_include_directories(${component} ${include_type} ${include_dir})
  endforeach()

  # add private includes
  foreach(include_dir ${COMPONENT_PRIV_INCLUDEDIRS})
    if (${include_type} STREQUAL INTERFACE)
      message(FATAL_ERROR "Component ${component} can't have no source files and COMPONENT_PRIV_INCLUDEDIRS set.")
    endif()
    get_filename_component(include_dir ${include_dir} ABSOLUTE BASE_DIR ${component_dir})
    target_include_directories(${component} PRIVATE ${include_dir})
  endforeach()

endfunction(register_component)

function(register_config_only_component)
  get_filename_component(component_dir ${CMAKE_CURRENT_LIST_FILE} DIRECTORY)
  get_filename_component(component ${component_dir} NAME)

  # No-op for now...
endfunction(register_config_only_component)

function(components_finish_registration)
  # each component should see the include directories of each other
  #
  # (we can't do this until all components are registered, because if(TARGET ...) won't work
  foreach(a ${COMPONENTS} ${CMAKE_PROJECT_NAME}.elf)
    if (TARGET ${a})
      get_target_property(a_type ${a} TYPE)
      if (${a_type} STREQUAL STATIC_LIBRARY OR ${a_type} STREQUAL EXECUTABLE)
        foreach(b ${COMPONENTS})
          if (TARGET ${b} AND NOT ${a} STREQUAL ${b})
            # Add all public compile options from b in a
            target_include_directories(${a} PRIVATE
              $<TARGET_PROPERTY:${b},INTERFACE_INCLUDE_DIRECTORIES>)
            target_compile_definitions(${a} PRIVATE
              $<TARGET_PROPERTY:${b},INTERFACE_COMPILE_DEFINITIONS>)
            target_compile_options(${a} PRIVATE
              $<TARGET_PROPERTY:${b},INTERFACE_COMPILE_OPTIONS>)
          endif()
        endforeach(b)
      endif(${a_type} STREQUAL STATIC_LIBRARY OR ${a_type} STREQUAL EXECUTABLE)

      if (${a_type} MATCHES .+_LIBRARY)
        set(COMPONENT_LIBRARIES "${COMPONENT_LIBRARIES};${a}")
      endif()
    endif()
  endforeach()

  # Embedded binary & text files
  spaces2list(COMPONENT_EMBED_FILES)
  foreach(embed_src ${COMPONENT_EMBED_FILES})
    target_add_binary_data(${component} "${embed_src}" BINARY)
  endforeach()
  spaces2list(COMPONENT_EMBED_TXTFILES)
  foreach(embed_src ${COMPONENT_EMBED_TXTFILES})
    target_add_binary_data(${component} "${embed_src}" TEXT)
  endforeach()

  target_link_libraries(${CMAKE_PROJECT_NAME}.elf ${COMPONENT_LIBRARIES})

endfunction(components_finish_registration)