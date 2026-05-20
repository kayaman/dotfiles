function handler(event) {
  event.request.uri = '${rewrite_path}';
  return event.request;
}
