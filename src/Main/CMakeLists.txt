add_executable(CAMX main.cpp)
target_link_libraries(CAMX PRIVATE camx_gui)

# Windows GUI 程序（不弹控制台）
set_target_properties(CAMX PROPERTIES WIN32_EXECUTABLE TRUE)
