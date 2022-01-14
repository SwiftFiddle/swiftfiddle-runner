#!/bin/bash

echo "$(swift --version)" > /TEMP/version

exec 1> /TEMP/stdout
exec 2> /TEMP/stderr

if [ "$_COLOR" = true ] ; then
  export TERM=xterm-256color
  sh /TEMP/faketty.sh $@ /TEMP/main.swift
else
  $@ /TEMP/main.swift
fi
