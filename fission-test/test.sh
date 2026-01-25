#!/bin/bash

# Test script for dir-0fission

setup_test_env() {
    # Use existing SourceDir but copy to test location to avoid git conflicts
    if [[ ! -d "SourceDir" ]]; then
        echo "ERROR: SourceDir not found. Please ensure it exists in the current directory."
        exit 1
    fi
    
    # Copy SourceDir contents to test_source
    cp -r SourceDir test_source
}

cleanup_test_env() {
    rm -rf test_source test_target test_copy
}

assert_file_exists() {
    local file_path="$1"
    local description="$2"
    
    if [[ ! -f "$file_path" ]]; then
        echo "FAIL: $file_path should exist"
        exit 1
    fi
}

assert_file_not_exists() {
    local file_path="$1"
    local description="$2"
    
    if [[ -f "$file_path" ]]; then
        echo "FAIL: $file_path should not exist"
        exit 1
    fi
}

test_fission() {
    set -e
    echo "Setting up test environment..."
    setup_test_env
    
    echo "Running dir-fission..."
    ../dir-fission test_source test_target
    
    echo "Running assertions..."
    
    # Assert only the non-mp4 video files have been moved to target

    for video_file in 'hi spaces.mkv' a.MOV a.mkv a.avi subdir/b.mov
    do
        assert_file_exists "test_target/$video_file" 
        assert_file_not_exists "test_source/$video_file"
    done

    for non_video_file in a b.txt a.mp4 a.m4v 'hi spaces.mp4' 'hi spaces.txt' subdir/subsubdir/c.{gif,mp4,nfo,txt}
    do
        assert_file_exists "test_source/$non_video_file"
        assert_file_not_exists "test_target/$non_video_file" 
    done

    echo "All tests passed!"
    cleanup_test_env
}

# Run the test
cleanup_test_env
test_fission