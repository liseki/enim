# ENim
Embedded Nim template compiler that is still work in progress.


## Overview
ENim allows embedding Nim code into a text template using the switches ```<% %>```. It is inspired by and similar to ERB in the Ruby programming language. The opening ```<%``` can be immediately followed by a directive as follows:

1. No directive means the Nim code is simply evaluated e.g. ```<% if true: %>```
2. Substitution directive evaluates the Nim code and inserts its result into the template e.g. ```<%= greet(person) %>```
3. Comment directive simply ommits the text from the template output e.g. ```<%# This is just a comment %>```
4. Tag directive creates an anchor point for injecting another template e.g. ```<%@ content "footer" %>```


## Why?
Apart from the templating ability, what's interesting about ENim is its performance goal. While the template output can be a string its intermediate state is as an ```IOMap``` object or tree. Instead of concatenating strings together to achive the output, an IOMap builds a hierarcy tree of the strings. In a template any regular (non-substituted) text is stored as a constant, in essence caching it and given a socket, the IOMap can be written to it without any concatenation using the UNIX ```writev``` call. This is inspired by how Erlang handles strings using IOList.


## Sample
Here's a sample template
```
<!DOCTYPE html>
<html>
  <head>
    <title>Using ENim</title>
    <%= csrf_meta_tags() %>
    <%= csp_meta_tag() %>

    <%@ content "assets": %>
      <%= stylesheet_link_tag("application", true) %>
      <%= javascript_include_tag("application", true) %>
    <% end %>
  </head>

  <body>
    <%@ yield %>

    <footer>
      <%@ content "footer": %>
        <p>&copy; 2019 MyCraft Ltd.</p>
      <% end %>
    </footer>
  </body>
</html>
```
