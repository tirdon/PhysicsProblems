const originalGetRandomValues = crypto.getRandomValues.bind(crypto);
crypto.getRandomValues = function(array) {
  if (array && array.buffer && array.buffer.constructor.name === 'SharedArrayBuffer') {
    const temp = new Uint8Array(array.length);
    originalGetRandomValues(temp);
    array.set(temp);
    return array;
  }
  return originalGetRandomValues(array);
};
