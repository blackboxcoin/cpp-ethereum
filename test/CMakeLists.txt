cmake_policy(SET CMP0015 NEW)

aux_source_directory(. SRC_LIST)
list(REMOVE_ITEM SRC_LIST "./createRandomVMTest.cpp")
list(REMOVE_ITEM SRC_LIST "./createRandomStateTest.cpp")
list(REMOVE_ITEM SRC_LIST "./checkRandomVMTest.cpp")
list(REMOVE_ITEM SRC_LIST "./checkRandomStateTest.cpp")

if (NOT JSONRPC)
	list(REMOVE_ITEM SRC_LIST "./AccountHolder.cpp")
endif()

include_directories(BEFORE ${JSONCPP_INCLUDE_DIRS})
include_directories(BEFORE ..)
include_directories(${Boost_INCLUDE_DIRS})
include_directories(${CRYPTOPP_INCLUDE_DIRS})
include_directories(${JSON_RPC_CPP_INCLUDE_DIRS})


file(GLOB HEADERS "*.h")
add_executable(testeth ${SRC_LIST} ${HEADERS})
add_executable(createRandomVMTest createRandomVMTest.cpp vm.cpp TestHelper.cpp Stats.cpp)
add_executable(createRandomStateTest createRandomStateTest.cpp TestHelper.cpp Stats.cpp)
add_executable(checkRandomVMTest checkRandomVMTest.cpp vm.cpp TestHelper.cpp Stats.cpp)
add_executable(checkRandomStateTest checkRandomStateTest.cpp TestHelper.cpp Stats.cpp)

target_link_libraries(testeth ${Boost_UNIT_TEST_FRAMEWORK_LIBRARIES})
target_link_libraries(testeth ${CURL_LIBRARIES})
target_link_libraries(testeth ethereum)
target_link_libraries(testeth ethcore)
target_link_libraries(testeth secp256k1)
target_link_libraries(testeth solidity)
if (NOT HEADLESS AND NOT JUSTTESTS)
	target_link_libraries(testeth webthree)
	target_link_libraries(testeth natspec)
endif()
if (JSONRPC)
	target_link_libraries(testeth web3jsonrpc)
	target_link_libraries(testeth ${JSON_RPC_CPP_CLIENT_LIBRARIES})
endif()

target_link_libraries(createRandomVMTest ${Boost_UNIT_TEST_FRAMEWORK_LIBRARIES})
target_link_libraries(createRandomVMTest ethereum)
target_link_libraries(createRandomVMTest ethcore)
target_link_libraries(createRandomStateTest ${Boost_UNIT_TEST_FRAMEWORK_LIBRARIES})
target_link_libraries(createRandomStateTest ethereum)
target_link_libraries(createRandomStateTest ethcore)
target_link_libraries(checkRandomVMTest ${Boost_UNIT_TEST_FRAMEWORK_LIBRARIES})
target_link_libraries(checkRandomVMTest ethereum)
target_link_libraries(checkRandomVMTest ethcore)
target_link_libraries(checkRandomStateTest ${Boost_UNIT_TEST_FRAMEWORK_LIBRARIES})
target_link_libraries(checkRandomStateTest ethereum)
target_link_libraries(checkRandomStateTest ethcore)

