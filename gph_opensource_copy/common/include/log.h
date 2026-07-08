#pragma once

#include <stdio.h>
#include <execinfo.h>
#include <fmt/core.h>
#include <unistd.h>

#define STAT	0
#define FATAL	1
#define ERROR	2
#define WARN	3
#define INFO	4
#define DEBUG	5
#define PRINT_LEVELS	6

const char * const MEGA_PRINT_MSG[] = {"STAT", "FATAL", "ERROR", "WARN",
                                       "INFO", "DEBUG"};

#ifndef MEGA_PRINT_LEVEL
#define MEGA_PRINT_LEVEL		INFO
#endif

// #define log(lvl, format, arg...) \
		// do { \
		// 	if (lvl <= MEGA_PRINT_LEVEL) { \
		// 		fmt::print(stderr, "[{} {}] ", getpid(), MEGA_PRINT_MSG[lvl]); \
        //         fmt::print(stderr, format, ##arg); \
		// 		fmt::print(stderr, "\n");\
		// 	} \
		// } while (0)
		
#define vclog(lvl, format, arg...) \
		do { \
			if (lvl <= MEGA_PRINT_LEVEL) { \
				fmt::print(stderr, "[{} {}] ", getpid(), MEGA_PRINT_MSG[lvl]); \
                fmt::print(stderr, format, ##arg); \
				fmt::print(stderr, "\n");\
			} \
		} while (0)

#define panic(format, arg...) \
		do {\
			fmt::print(stderr, "[{} {}] ", getpid(), MEGA_PRINT_MSG[FATAL]); \
			fmt::print(stderr, format, ##arg); \
			fmt::print(stderr, "\n");\
			exit(-1); \
		} while (0)

